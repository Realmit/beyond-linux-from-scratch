#!/usr/bin/env python3
import subprocess

def check_service(service):
    try:
        subprocess.run(["svc", "status", service], check=True, capture_output=True)
        print(f" {service} is running")
    except:
        print(f" {service} is not running")

def main():
    for svc in ["network", "sshd", "dbus", "lightdm"]:
        check_service(svc)

if __name__ == "__main__":
    main()