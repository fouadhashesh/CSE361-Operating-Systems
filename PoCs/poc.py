import paramiko
import sys

ROUTER_IP = "192.168.1.2"
USERNAME = "root"
PASSWORD = "root"   # use SSH keys in real usage

COMMANDS = ["mkdir isitworking"]

def run():
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())

    try:
        client.connect(
            hostname=ROUTER_IP,
            username=USERNAME,
            password=PASSWORD,
            look_for_keys=False,
            allow_agent=False,
            timeout=10
        )

        for cmd in COMMANDS:
            stdin, stdout, stderr = client.exec_command(cmd)
            exit_status = stdout.channel.recv_exit_status()

            out = stdout.read().decode()
            err = stderr.read().decode()

            print(f"$ {cmd}")
            if out:
                print(out.strip())
            if err:
                print(err.strip(), file=sys.stderr)

            if exit_status != 0:
                print("Command failed, aborting.")
                break

    finally:
        client.close()

if __name__ == "__main__":
    run()

