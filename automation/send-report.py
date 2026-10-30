"""Emails one triage report. Usage: python3 send-report.py <subject> <body-file>

Reads REPORT_TO, SMTP_HOST, SMTP_PORT (587 STARTTLS or 465 SSL), SMTP_USER, SMTP_PASSWORD and
SMTP_FROM from the environment (triage-hourly.sh loads them from its env file).
"""
import os
import smtplib
import sys
from email.message import EmailMessage

subject, body_file = sys.argv[1], sys.argv[2]
env = os.environ
for name in ("REPORT_TO", "SMTP_HOST", "SMTP_USER", "SMTP_PASSWORD"):
    if not env.get(name):
        sys.exit(f"{name} is not set")

msg = EmailMessage()
msg["Subject"] = subject
msg["From"] = env.get("SMTP_FROM") or env["SMTP_USER"]
msg["To"] = env["REPORT_TO"]
msg.set_content(open(body_file, encoding="utf-8").read())

port = int(env.get("SMTP_PORT") or 587)
if port == 465:
    server = smtplib.SMTP_SSL(env["SMTP_HOST"], port, timeout=30)
else:
    server = smtplib.SMTP(env["SMTP_HOST"], port, timeout=30)
    server.starttls()
with server:
    server.login(env["SMTP_USER"], env["SMTP_PASSWORD"])
    server.send_message(msg)
print(f"sent to {env['REPORT_TO']}")
