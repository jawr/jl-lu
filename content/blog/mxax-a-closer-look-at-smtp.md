---
title: "mx.ax - a closer look at SMTP"
date: 2021-01-20T09:56:13+09:00
slug: "mx.ax - a closer look at SMTP"
description: "mx.ax - A more in depth look at the design and the reasoning behind it"
keywords: ["mx.ax", "smtp", "go", "design"]
draft: false
tags: ["mx.ax", "smtp", "go", "design"]
math: false
toc: false
---
# SMTP
Simple Mail Transfer Protocol has been around for a long time and although it
has been revised, extended and abused beyond its original intent, it does remain
relatively simple. 

If you want to send an email to `yourfriend@domain.com` your
client first needs to use DNS to discover where to send the email. This
information is stored within the MX record, i.e. for `lawrence.pm`:

```
;; QUESTION SECTION:
;lawrence.pm.                   IN      MX

;; ANSWER SECTION:
lawrence.pm.            10800   IN      MX      20 helo.mx.ax.
lawrence.pm.            10800   IN      MX      10 ehlo.mx.ax.

;; ^ domain             ^ ttl            priority^ ^server
```

Lower priority MX records should be attempted first. 

Once the Mail eXchange has been identified the client can attempt to connect and
begin. SMTP uses a text based protocol, much like many other protocols of it's
era (*looks at FTP & HTTP*) Typically an SMTP submission looks like so:

```
# >>> denotes client message
# <<< denotes server message

<<< 220 My Fancy SMTP server welcome message
>>> EHLO <FQDN or Address>
<<< 250 Greetings

# foreach email do
	>>> MAIL FROM: <sender@place.com>
	<<< 250 OK
	# foreach recipient do
		>>> RCPT TO: <jl.lu@lawrence.pm>
		<<< 250 OK
	# end foreach
	>>> DATA
	<<< 354 End data with <CR><LF>.<CR><LF>
	>>> <Headers and Email>
	>>> .
	<<< 250 OK
# end foreach

>>> QUIT
<<< 221 Ciao
```

## Submission and Relay
Submission is the starting point for an email, an email client connects to the
SMTP server (typically port 587). Relay is when SMTP servers pass emails with
each other over port 25, i.e. when gmail sends me an email, their SMTP servers
will connect to `ehlo.mx.ax` on port 25.

There are other protocols for receiving emails as a client, such as IMAP and
POP.

## Rejection
During an SMTP exchange the server can reject the message at various stages,
below are some examples:

- `<FQDN or Address>` given found in a Block List 
- `<MAIL FROM>` is blacklisted.
- `<MAIL FROM>` [SPF](https://en.wikipedia.org/wiki/Sender_Policy_Framework)
  denies sending via `<FQDN or Address>`
- There is no route to `<RCPT TO>` via this MX
- `<Headers and Email>` rejected (Spam filter, [DKIM](https://en.wikipedia.org/wiki/DomainKeys_Identified_Mail)
  failure, etc)
