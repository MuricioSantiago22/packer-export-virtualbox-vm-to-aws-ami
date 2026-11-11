# packer-export-virtualbox-vm-to-aws-ami

Export a VirtualBox VM (`vm1`) to OVA, provision NGINX with Packer and import it to AWS as an AMI.

- `json/config.json`: Packer JSON template, SSH credentials hardcoded.
- `hcl/config.hcl` + `hcl/variables.hcl`: Packer HCL template, SSH credentials read from a variables file.
- `scripts/install-nginx.sh`: shell provisioner.

## Notes

- Packer templates use the `virtualbox-vm` builder on the existing VM `vm1`, as the assignment asks. `virtualbox-ovf` was used in the first version and replaced after review.
- `vm1` was installed with **BIOS** firmware, so the AMI is imported with `boot_mode = "legacy-bios"`. The tip suggests `"uefi"`, which only boots if the VM was installed with EFI; enabling EFI on a BIOS-installed VM does not make it boot.
- `vm1` uses a bridged NIC. The templates switch NIC 1 to NAT with `vboxmanage` so Packer can reach SSH through a forwarded port.
- SSH credentials are hardcoded in `json/config.json` and read from `hcl/variables.hcl` in the HCL template, as the assignment asks. Change the password on the VM and in both files before making the repo public.

## Part 1: VBoxManage export + aws ec2 import-image

### AWS setup (once)

VM Import needs an S3 bucket and a service role named `vmimport`.

```bash
BUCKET=packer-vm-import-mauricio-2026
REGION=us-east-2

aws s3 mb s3://$BUCKET --region $REGION

cat > trust-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "vmie.amazonaws.com" },
    "Action": "sts:AssumeRole",
    "Condition": { "StringEquals": { "sts:Externalid": "vmimport" } }
  }]
}
EOF

cat > role-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetBucketLocation", "s3:GetObject", "s3:ListBucket", "s3:PutObject", "s3:GetBucketAcl"],
      "Resource": ["arn:aws:s3:::$BUCKET", "arn:aws:s3:::$BUCKET/*"]
    },
    {
      "Effect": "Allow",
      "Action": ["ec2:ModifySnapshotAttribute", "ec2:CopySnapshot", "ec2:RegisterImage", "ec2:Describe*"],
      "Resource": "*"
    }
  ]
}
EOF

aws iam create-role --role-name vmimport --assume-role-policy-document file://trust-policy.json
aws iam put-role-policy --role-name vmimport --policy-name vmimport --policy-document file://role-policy.json
```

### Export the VM

The VM must be powered off, with one disk and no ISO attached.

```bash
VBoxManage showvminfo vm1 --machinereadable | grep -i firmware   # BIOS or EFI

VBoxManage export vm1 \
  --output export/vm1.ova \
  --ovf20 \
  --options manifest,nomacs
```

| Flag | Why |
|---|---|
| `--output vm1.ova` | Single-file OVF package, the format AWS imports directly |
| `--ovf20` | OVF 2.0 format |
| `--options manifest` | Writes the `.mf` checksum file |
| `--options nomacs` | Drops the VirtualBox MAC addresses so the network comes up on EC2 |

### Import to AWS

```bash
aws s3 cp export/vm1.ova s3://$BUCKET/vm-import/vm1.ova

cat > containers.json <<EOF
[
  {
    "Description": "vm1 exported from VirtualBox",
    "Format": "ova",
    "UserBucket": { "S3Bucket": "$BUCKET", "S3Key": "vm-import/vm1.ova" }
  }
]
EOF

aws ec2 import-image --region $REGION \
  --description "vm1 from VirtualBox" \
  --disk-containers file://containers.json \
  --boot-mode legacy-bios

# Repeat until Status is "completed" (20 to 60 min); the last column is the AMI ID
aws ec2 describe-import-image-tasks --region $REGION \
  --import-task-ids import-ami-XXXXXXXX \
  --query "ImportImageTasks[0].[Status,Progress,StatusMessage,ImageId]"
```

### Launch an EC2 instance from the AMI

Use a `t3.micro`.

```bash
MY_IP=$(curl -s https://checkip.amazonaws.com)

SG=$(aws ec2 create-security-group --region $REGION --group-name vm1-sg \
  --description "SSH from my IP and HTTP" --query GroupId --output text)
aws ec2 authorize-security-group-ingress --region $REGION --group-id $SG --protocol tcp --port 22 --cidr $MY_IP/32
aws ec2 authorize-security-group-ingress --region $REGION --group-id $SG --protocol tcp --port 80 --cidr 0.0.0.0/0

aws ec2 run-instances --region $REGION --image-id ami-XXXXXXXX --instance-type t3.micro \
  --security-group-ids $SG \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=vm1-import-cli}]"

aws ec2 describe-instances --region $REGION --filters "Name=tag:Name,Values=vm1-import-cli" \
  --query "Reservations[].Instances[].[InstanceId,State.Name,PublicIpAddress]" --output table

ssh mau@PUBLIC_IP
```

If it does not answer, check the boot log with `aws ec2 get-console-output --region $REGION --instance-id i-XXXXXXXX --latest --output text`.

## Parts 2 and 3: Packer

Both templates use the `virtualbox-vm` builder on the existing VM `vm1`. Before running:

- `vm1` is registered in VirtualBox and **powered off**.
- The AMI is imported with `boot_mode = "legacy-bios"`, matching the BIOS firmware of `vm1`.
- The `vmimport` role and the bucket from Part 1 exist.
- AWS credentials are set (`aws configure` or `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`).

Packer boots `vm1`, installs NGINX through the shell provisioner, shuts it down, exports it to an `output-*/` folder as `.ova` and the `amazon-import` post-processor uploads it to S3 and registers the AMI.

JSON:

    cd json && packer build config.json

HCL (Packer needs the `.pkr.hcl` extension, so use a copy or symlink):

    cd hcl && ln -sf config.hcl config.pkr.hcl
    packer init config.pkr.hcl
    packer build -var-file=variables.hcl config.pkr.hcl

The last line of the build shows the AMI (`us-east-2: ami-...`). Launch it like in Part 1 and open `http://PUBLIC_IP`: it shows **"NGINX instalado con Packer"**.

## Cleanup

```bash
aws ec2 terminate-instances --region $REGION --instance-ids i-XXXXXXXX
aws ec2 deregister-image --region $REGION --image-id ami-XXXXXXXX
aws ec2 delete-snapshot --region $REGION --snapshot-id snap-XXXXXXXX
aws s3 rm s3://$BUCKET --recursive
```
