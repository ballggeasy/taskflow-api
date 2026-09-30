# Stand-in for the provisioned host: LocalStack does not boot real VMs, so Ansible
# configures this SSH-reachable container that carries the Terraform instance's name.
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends openssh-server python3 ca-certificates \
 && mkdir -p /run/sshd /root/.ssh && rm -rf /var/lib/apt/lists/*
CMD ["sh", "-c", "echo \"$PUBKEY\" > /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys && exec /usr/sbin/sshd -D -e"]
