package security

import rego.v1

# Input: `npm audit --json` output.

# Clause 1: the audit summary reports at least one critical vulnerability.
deny contains msg if {
	count := input.metadata.vulnerabilities.critical
	count > 0
	msg := sprintf("dependency scan reports %d CRITICAL vulnerabilities", [count])
}

# Clause 2: any individual package is rated critical.
deny contains msg if {
	some name, vuln in input.vulnerabilities
	vuln.severity == "critical"
	msg := sprintf("package %s has a CRITICAL vulnerability", [name])
}
