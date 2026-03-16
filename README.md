# ansible-stig-rhel9

# ansible-stig-rhel9

**RHCE Ansible Apprenticeship — Project 2**

Automated DISA STIG compliance scanning, remediation, and reporting for RHEL 9 using Ansible and OpenSCAP. This project builds on the FreeIPA environment from Project 1 and implements a controlled test-before-prod workflow that mirrors how STIG remediation is managed on real government and DoD systems.

---

## Architecture

```
                        ┌─────────────────────────┐
                        │      Control Node        │
                        │   ansible-stig-rhel9/    │
                        │   ├── playbooks/         │
                        │   ├── group_vars/         │
                        │   ├── roles/              │
                        │   ├── inventory/          │
                        │   └── reports/            │
                        └────────────┬────────────-─┘
                                     │ SSH
               ┌─────────────────────┼─────────────────────┐
               │                     │                      │
    ┌──────────▼──────────┐ ┌────────▼────────┐  ┌─────────▼───────┐
    │     ipaclient1       │ │   ipaclient2    │  │   ipaclient3    │
    │                      │ │                 │  │                 │
    │   [ test group ]     │ │ [ prod group ]  │  │ [ prod group ]  │
    │                      │ │                 │  │                 │
    │  Remediation applied │ │  Only promoted  │  │  Only promoted  │
    │  here first          │ │  after test     │  │  after test     │
    │  Verified before     │ │  passes         │  │  passes         │
    │  promoting to prod   │ │                 │  │                 │
    └──────────────────────┘ └─────────────────┘  └─────────────────┘

  Workflow:  scan all → research findings → remediate test →
             verify test → promote to prod → scan all → compare scores
```

### Inventory Groups

```ini
[test]
ipaclient1

[prod]
ipaclient2
ipaclient3

[stig_targets:children]
test
prod
```

`stig_targets` is used for scans and package installs. `test` and `prod` are used for remediation — rules are applied to `test` first, verified, then promoted to `prod`.

---

## Prerequisites

| Requirement | Details |
|---|---|
| OS | RHEL 9 (required — SCAP content is version-specific) |
| Subscription | Active Red Hat subscription on all managed nodes |
| Project 1 | Completed — FreeIPA clients enrolled and accessible |
| Control node | Ansible installed, SSH key access to all managed nodes |
| Managed node packages | `openscap-scanner`, `scap-security-guide` (installed by `install_openscap.yml`) |
| Disk space | 500 MB free per managed node for scan reports |

Verify subscription status before running anything:
```bash
ansible stig_targets -m command -a 'subscription-manager status' --become
```

---

## Project Structure

```
ansible-stig-rhel9/
├── ansible.cfg                      # Inventory path, SSH config
├── requirements.yml                 # RedHatOfficial.rhel9_stig role declaration
├── inventory/
│   └── hosts.ini                    # test (ipaclient1) and prod (ipaclient2/3) groups
├── group_vars/
│   └── stig_targets.yml             # DISA_STIG_RHEL_09_* toggle file + value overrides
├── roles/
│   └── RedHatOfficial.rhel9_stig/   # Installed by ansible-galaxy, gitignored
├── playbooks/
│   ├── site.yml                     # Master playbook — full scan/remediate/scan workflow
│   ├── install_openscap.yml         # Installs openscap-scanner and scap-security-guide
│   ├── scan.yml                     # Runs oscap scan and fetches HTML reports
│   └── remediate.yml                # Applies STIG remediation via RedHatOfficial role
├── reports/                         # Generated scan reports, gitignored
│   ├── pre_remediation/
│   └── post_remediation/
└── docs/
    ├── control_research.md          # Per-control research notes
    └── remediation_summary.md       # Pre/post compliance scores per host
```

---

## Role Dependency

The remediation role is declared in `requirements.yml`:

```yaml
---
roles:
  - name: RedHatOfficial.rhel9_stig
```

Install into the project-local roles directory:

```bash
ansible-galaxy role install -r requirements.yml -p ./roles
```

Source: [https://github.com/RedHatOfficial/ansible-role-rhel9-stig](https://github.com/RedHatOfficial/ansible-role-rhel9-stig)

---

## Toggle File

All STIG rule toggles live in `group_vars/stig_targets.yml`. The `DISA_STIG_RHEL_09_*` variables are copied from the role's `defaults/main.yml` and set to `false` by default. Rules are enabled deliberately one at a time or in small groups.

```yaml
---
# ============================================================
# STIG Rule Toggle File — group_vars/stig_targets.yml
# true  = apply this rule during remediation
# false = skip this rule
# ============================================================

# Required override — prevents FIPS from breaking the lab
var_system_crypto_policy: DEFAULT

# CAT I — High Severity
DISA_STIG_RHEL_09_211010: true   # Keep system patched
DISA_STIG_RHEL_09_255045: true   # Disable SSH root login
DISA_STIG_RHEL_09_431010: true   # Disable ctrl-alt-del reboot
DISA_STIG_RHEL_09_672010: false  # FIPS mode — SKIP: requires full OS reinstall

# CAT II — Medium Severity
DISA_STIG_RHEL_09_653010: true   # Enable auditd
DISA_STIG_RHEL_09_412010: true   # Account lockout threshold
DISA_STIG_RHEL_09_611010: false  # PAM password settings  — SKIP: FreeIPA manages PAM
DISA_STIG_RHEL_09_611015: false  # PAM password complexity — SKIP: FreeIPA manages PAM

# CAT III — Low Severity
DISA_STIG_RHEL_09_291010: true   # Set login banner
DISA_STIG_RHEL_09_291015: true   # Set SSH login banner
DISA_STIG_RHEL_09_271040: false  # Disable kdump — SKIP: needed for lab debugging
```

Every `false` entry with a comment is a documented exception — the Ansible equivalent of a POAM item.

To find the variable name for any rule, look it up in the role's defaults on GitHub:
[https://github.com/RedHatOfficial/ansible-role-rhel9-stig/blob/main/defaults/main.yml](https://github.com/RedHatOfficial/ansible-role-rhel9-stig/blob/main/defaults/main.yml)

---

## Usage

### Install the role
```bash
ansible-galaxy role install -r requirements.yml -p ./roles
```

### Run the full workflow (scan → remediate → scan)
```bash
ansible-playbook playbooks/site.yml --become
```

### Scan only — no changes made
```bash
ansible-playbook playbooks/site.yml --tags scan --become
```

### Remediate test group only (always start here)
```bash
# Check mode first — see what would change without touching anything
ansible-playbook playbooks/remediate.yml --check --become -l test

# Apply to test
ansible-playbook playbooks/remediate.yml --become -l test
```

### Promote to prod after verifying test
```bash
ansible-playbook playbooks/remediate.yml --become -l prod
```

### Apply by CAT level (phased approach)
```bash
# CAT I first — these are the showstoppers
ansible-playbook playbooks/remediate.yml --become -l test --tags CAT1

# CAT II after CAT I is verified
ansible-playbook playbooks/remediate.yml --become -l test --tags CAT2

# CAT III last
ansible-playbook playbooks/remediate.yml --become -l test --tags CAT3
```

### Open scan reports
```bash
cd /home/automation/ansible-stig-rhel9/reports
python3 -m http.server 8080
# Browse to http://<control-node-ip>:8080/pre_remediation/
```

---

## Compliance Results

| Host | Group | Pre-Remediation | Post-Remediation | CAT I Resolved | Exceptions |
|---|---|---|---|---|---|
| ipaclient1 | test | — | — | — | — |
| ipaclient2 | prod | — | — | — | — |
| ipaclient3 | prod | — | — | — | — |

*Update this table after completing Tasks 3 and 6.*

---

## Documented Exceptions

| RHEL ID | V-Number | CAT | Rule | Reason |
|---|---|---|---|---|
| RHEL-09-672010 | V-258139 | I | Enable FIPS mode | Requires full OS reinstall — not applicable to lab |
| RHEL-09-611010 | V-258053 | II | PAM password settings | FreeIPA manages PAM — applying this rule breaks FreeIPA authentication |
| RHEL-09-611015 | V-258054 | II | PAM password complexity | FreeIPA manages PAM — same reason as above |
| RHEL-09-271040 | V-257987 | III | Disable kdump | Required for kernel debugging in lab environment |

---

## Key File Locations on Managed Nodes

| Path | Description |
|---|---|
| `/usr/share/xml/scap/ssg/content/ssg-rhel9-ds.xml` | SCAP source data stream — input to all `oscap` scan commands |
| `/usr/share/scap-security-guide/ansible/rhel9-playbook-stig.yml` | Pre-built STIG remediation playbook from `scap-security-guide` package |
| `xccdf_org.ssgproject.content_profile_stig` | STIG profile ID used in `oscap` scan commands |

---

## References

| Resource | URL |
|---|---|
| RedHatOfficial STIG Role (GitHub) | https://github.com/RedHatOfficial/ansible-role-rhel9-stig |
| Role defaults — all toggle variables | https://github.com/RedHatOfficial/ansible-role-rhel9-stig/blob/main/defaults/main.yml |
| STIG Viewer — browse RHEL 9 controls | https://www.stigviewer.com/stigs/red_hat_enterprise_linux_9 |
| DISA Cyber Exchange — official STIG downloads | https://www.cyber.mil/stigs/ |
| ComplianceAsCode upstream source | https://github.com/ComplianceAsCode/content |

---

## License

MIT
