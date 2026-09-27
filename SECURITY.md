# Security

## Reporting a new marker, hiding place or false negative

If you found a backdoor that stayclean misses, please **don't post live payloads or stolen
data in a public issue.** Instead:

- Open a GitHub **private security advisory** on this repo (Security → Report a vulnerability), or
- Open a public issue with only the *pattern* (where it hid and how it was hidden), not the payload.

Useful details: where the code lived (path pattern), how it was hidden (padding, encoding,
file type), any unique marker strings, and how it persisted or started.

## Reporting a bug in stayclean itself

Same channels. stayclean is read-only by design; anything that makes it execute code from
what it scans, write outside `~/.stayclean`, or send more than the one-line summary is a
security bug.

Maintainer: Soroush Osivand ([@SoroushOsivand](https://github.com/SoroushOsivand))
