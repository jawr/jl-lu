---
title: "mx.ax - an email service for two"
date: 2021-01-19T11:11:57+09:00
slug: "mx.ax - an email service for two"
description: "mx.ax - How I created an email service that isn't used"
keywords: ["mx.ax", "smtp", "go", "dns"]
draft: false
tags: ["mx.ax", "smtp", "go", "dns"]
math: false
toc: false
---
## The Premise
A friend of mine is addicted to domain names. He has an inordinate amount at his
disposal and in his pursuit of more often finds himself needing services and
scripts. 

Among many of his requests was an email service to let him easily use these
domains for email, without having to leave the comfortable indoctrination of our
overlord Google. 

His requirements were roughly:

- Add and remove domain names for use.
- Send and receive emails.
- Have them setup in a secure way ticking as many industry
  standards/requirements as possible.
- Be able to add and remove arbitrary "routes", i.e. `hi@mx.ax` could be sent to
  `friend@gmail.com` one day and then `buddy@hotmail.com` the next.
- Avoid JavaScript.

## Similar services
A little research led me to service with very similar intent called [Forward
Email](https://forwardemail.net/en).  However its ultra privacy focus was a
little too strict for our liking as we felt a customizable level of logging
would be useful for us as users.

[MXroute](https://mxroute.com/) is another great service for hosting your
domains for email, from my research it appears to package opensource projects on
their infrastructure and. It is also intended to replace and handle your entire
email service.

## Technologies
This was easy to decide on as I am currently engaged to *Go* and avoiding
JavaScript meant I didn't have to create anything overkill with React or one of
it's colleagues.

Parts of the service were to be split in to discrete services that would share a
common codebase. These services would communicate over a Message Queue (*RabbitMQ*
namely for it's persistence features). 

Having the services communicate over an MQ means that we are easily able to
scale as they are naturally partitioned and if a particular queue were to start
generating too high a latency then it's possible to start more services that
consume from that particular queue.

All state will be persisted in a central database which will take the form of a
*PoatgreSQL* database. The database will utilise Row Level Security to create a
[multi-tenant](https://aws.amazon.com/blogs/database/multi-tenant-data-isolation-with-postgresql-row-level-security/) setup allowing data isolation.

*Nginx* will be used as an SMTP load balancer and a reverse proxy for serving
HTTP. It will also be the way in which we automate/renew TLS certificates for
both SMTP and HTTP using *LetsEncrypt*.


## Infrastructure
Email and its related protocols are in not very intense, so we would not need
any specialised hardware. Apart from RabbitMQ and PostgreSQL, mx.ax is designed
in a way so that its partitioned in to smaller, discrete services means that we
can distribute and scale as and when needed.

However redundancy is very important, email should always be available and so
having backup infrastructure on a different network is ideal. Both RabbitMQ and
PostgreSQL can be setup in ways to provide high availability. We will be running
them on a single instance with backup mechanisms in place. Our failover will be
in the form of a special lower priority MX that will save all messages in a form
so that they can be replayed in to the primary system once issues have been
resolved (this has the issue of looking like an open relay which might cause
some reputation issues, so ideally it will be wrapped in a circuit breaker so
that it is only enabled when issues are detected on the high priority MX).

One, if not the biggest issue with email based services arises from reputation;
all Email Services Providers try very hard to protect their users from spam
messages and one of the easiest ways to do this is championed by Google where
they allow senders to build a reputation that is a result of user interactions
with the messages. Senders with a low reputation are either rejected or have
their messages placed in spam. 

For this project we have access to a /24 IP space which allows us to build a
reputation from the ground up. We also use Domain Keys Identified Mail (DKIM) to
sign all forwarded mail which allows the ESP to verify the source and route of
mail sent from us.

