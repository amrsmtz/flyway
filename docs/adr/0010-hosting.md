# 10. Hosting on a free ARM virtual machine with Kamal

## Context

The demo must be online at no cost, and needs the full TimescaleDB (compression and continuous aggregates),
which free managed PostgreSQL tiers do not offer.

## Decision

One Oracle Cloud ARM virtual machine (2 cores, 12 GB) running three containers deployed with Kamal: the web
app, a job container for ingestion, and TimescaleDB as an accessory, reachable only from the machine itself.
HTTPS comes from Kamal's proxy and Let's Encrypt.

## What it took

- The free ARM pool in Montreal was out of capacity for every size tried. Converting the account to
  pay-as-you-go, still within the always-free allowance, solved it at once; a budget alert at 1 dollar guards
  against surprises.
- Ports 80 and 443 must be opened twice: in the cloud network and in the instance's own firewall.
- Kamal recognises a git error by its English text; with a French git it rebuilt its clone on every deploy.
- The host name is `sslip.io`, which maps a name to the IP it contains. Dynamic-DNS services were blocked by
  the network the project was built on, and some corporate filters block `sslip.io` too.

## Alternatives considered

- **Managed platforms.** No full TimescaleDB on a free tier.
- **A home machine behind a tunnel.** Free and fully controlled, but tied to a home connection.
- **A small paid server.** A few dollars a month would remove the capacity question; kept as the fallback.

## Consequences

- Operations are mine: updates, firewall. No backup is configured: every table can be collected again from the
  feeds, at the cost of about two days of eBird quota.
- A deploy takes 20 to 90 seconds and replays pending migrations.
- A real domain name would be the first thing to buy for anything beyond a demo.
