---
title: "mx.ax - social schema distancing"
date: 2021-01-25T10:45:30+09:00
slug: "mx.ax the hows and why of the database schema design"
description: "The hows and whys of mx.ax's database schema design"
keywords: ["mx.ax", "design", "database", "postgresql"]
draft: false
tags: ["mx.ax", "design", "database", "postgresql"]
math: false
toc: false
---
## User isolation
When creating a service that contains users who don't require interaction with
one other, it's necessary to provide some assurances that their data will remain
isolated. There are various strategies to try and ensure this isolation, each
with their own benefits and issues. Below are the main ones:

- **Silo**, each user has their own database instance.
- **Bridge**, each user has their own database (schema) on a shared instance.
- **Pool**, each user uses the same database (schema) and instance.

Having more instances means higher isolation at the cost of increasing
maintenance and infrastructure complexity, but decreasing program responsibility
where errors are more likely to happen.

Having less instances means less maintenance and infrastructure complexity at
the cost of increased program complexity (read potential for errors). It also
means the infrastructure can be pooled together in to one resource allowing the
user to have access to more.

[AWS Database
Blog](https://aws.amazon.com/blogs/database/multi-tenant-data-isolation-with-postgresql-row-level-security/#data-partitioning-options)
has an exceptionally good break down of the previously mentioned models and the rationale behind
using Row Level Security, plus examples. 

I have worked at a company that initially used a Silo approach and moved to a
Bridge approach as it was the easiest to transition to, fit their service model
and offered a huge decrease in overheads and increase in performance. It was a
very pleasant experience and there weren't so many issues with on boarding and
maintenance.

## Row Level Security
RLS is a feature of Postgres that allows us to create policies on tables that
restrict operations depending on a condition. A common method is to use the
built in Access Control List (ACL) as our condition, this would mean that each
account has their own dedicated connection to the database and their connection
authentication details are used as the condition to restrict access to only
their data. The main issue with this design for our purposes is that we would be
wasting a lot of resources as Postgres connections are not light. 

Instead we will instead add an `account_id` column to all tables and then enable
the following policy:

```sql
CREATE TABLE domains (
	id SERIAL PRIMARY KEY,
	-- account_id used for integrity and isolation
	account_id INT NOT NULL REFERENCES accounts(id),
	name TEXT UNIQUE NOT NULL,
	verify_code TEXT UNIQUE NOT NULL,
	verified_at TIMESTAMP WITH TIME ZONE,
	expires_at DATE NOT NULL,
	created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
	updated_at TIMESTAMP WITH TIME ZONE,
	deleted_at TIMESTAMP WITH TIME ZONE
);

ALTER TABLE domains ENABLE ROW LEVEL SECURITY;

CREATE POLICY domains_isolation_policy ON domains
	USING (account_id = current_setting('mxax.current_account_id')::INT);
```

That policy essentially injects a `WHERE` conditional of:

`account_id = current_setting('mxax.current_account_id')::INT` 

in to every access of the `domains` table helping to prevent bugs where joins,
inner selects and other queries forget or incorrectly restrict the table to the
current account.

The connecting program only has to correctly set the namespaced postgres
variable `mxax.current_account_id` to the account, which can easily be set
during the life cycle of a transaction. Something the HTTP server can do on a
per request basis.

## Pros & Cons
Using this method we can ensure a high level of isolation that limits the
chances of human error introducing degradation. It allows us to reduce hardware
and maintenance costs as meaning accounts have access to a better service.

It does however create a smell in the form of "magic"; there are things
happening behind the scenes that are not explicit in the codebase. The schema
also becomes slightly more messy as it introduces foreign keys that are
redundant.

