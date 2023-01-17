#!/usr/bin/env bash

set -xe

_base_to_template() {
    base_vm=win10
    virsh shutdown $base_vm || true

    virsh dumpxml $base_vm >/etc/libvirt/qemu/template.xml
    rsync -avP /var/lib/libvirt/images/$base_vm.qcow2 /var/lib/libvirt/images/template.qcow2

    sed -i "s@/var/lib/libvirt/images/$base_vm.qcow2@/var/lib/libvirt/images/template.qcow2@" \
        /etc/libvirt/qemu/template.xml

    virt-sysprep -a /var/lib/libvirt/images/template.qcow2

    # virsh undefine basevm
    # rm /home/kvm/images/basevm.qcow2
}

_template_to_new() {
    read -rp "New VM name: " read_vm_name
    echo "VM name is: ${read_vm_name:? empty vm name}"
    virt-clone --connect qemu:///system \
        --original-xml /etc/libvirt/qemu/template.xml \
        --file /var/lib/libvirt/images/"$read_vm_name".qcow2 \
        --name "$read_vm_name"
}

case $1 in
b)
    _base_to_template
    ;;
n)
    _template_to_new
    ;;
esac
