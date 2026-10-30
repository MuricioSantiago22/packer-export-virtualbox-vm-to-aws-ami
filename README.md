# packer-export-virtualbox-vm-to-aws-ami

Export a VirtualBox VM (`vm1`) to OVA, provision NGINX with Packer and import it to AWS as an AMI.

- `json/config.json`: Packer JSON template, SSH credentials hardcoded.
- `hcl/config.hcl` + `hcl/variables.hcl`: Packer HCL template, SSH credentials read from a variables file.
- `scripts/install-nginx.sh`: shell provisioner.

The OVA is exported with:

    VBoxManage export vm1 --output export/vm1.ova --ovf10 --manifest

## Run

JSON:

    cd json && packer build config.json

HCL (Packer needs the `.pkr.hcl` extension, so use a copy or symlink):

    cd hcl && ln -sf config.hcl config.pkr.hcl
    packer init config.pkr.hcl
    packer build -var-file=variables.hcl config.pkr.hcl
