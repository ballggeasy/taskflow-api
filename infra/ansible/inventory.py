#!/usr/bin/env python3
"""Build an Ansible inventory from `terraform output -json` (file passed as argv[1])."""
import json
import sys

out = json.load(open(sys.argv[1]))
name = out["instance_name"]["value"]
addr = out["instance_address"]["value"]
print("[taskflow]")
print(f"{name} ansible_user=root ansible_ssh_private_key_file=/work/ansible_key tf_instance_address={addr}")
