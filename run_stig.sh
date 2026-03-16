#!/bin/bash

ansible-playbook playbooks/remediate.yml --limit ipaclient1 -i inventory/stig_hosts.yml
