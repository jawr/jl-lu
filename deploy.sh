#!/bin/bash
hugo -D
rsync -raz public/ jl.lu:/var/www/blog
