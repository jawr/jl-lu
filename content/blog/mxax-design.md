---
title: "Mxax Design"
date: 2021-01-25T10:44:33+09:00
draft: true
---

# Design
Armed with this overview of SMTP we can begin to extract some potential
services:
	
- SMTP server (submission & relay)
	- Responsible for processing incoming SMTP
- SMTP client (sender)
	- Responsible for processing outgoing SMTP
- User control panel 
	- Allow a user to control their account
- Logging
	- Central point for collecting log messages from the various services

## The Codebase 
Although Go doesn't enforce a project layout, there is a community created
[standard](https://github.com/golang-standards/project-layout) which is a nice
jumping off point for creating a consistency. 

For mx.ax the codebase there are four major directories:

- `cmd` - Each subdirectory is an app that compiles to a service.
- `internal` - Private application/library code. 
- `schema` - Database schema and fixtures.
- `templates` - HTML templates used by the control panel.



