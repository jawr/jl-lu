---
title: "it svelte good"
date: 2021-03-22T18:02:55+09:00
slug: "swapping out React for svelte"
description: "Refactoring a project from React to svelte"
keywords: ["svelte", "react"]
draft: true
tags: ["svelte", "react"]
math: false
toc: false
---
## React
I have been using React with Redux for many projects over the last few years and
although I appreciate the new design patterns it introduced me to and the
dynamic interfaces it allows, there has always been a slight annoyance with the
amount of boilerplate required when following particular recommended patterns.

Of course I appreciate that these patterns are mostly targeted at very large and
complex applications.

As an attempt to resolve this my most recent projects have used the classic
server side generated templates with small Javascript functionality added with
the tiny [AlpineJS](https://github.com/alpinejs/alpine). 

This was extremely refreshing at first and it felt like I was able to prototype
quickly, loading times also seemed to improve. 

However, as soon as some more complicated functionality was required (i.e.
spawning a modal that allowed a user to modify some data, then go back to the
previous screen and have those changes reflected without modifying pagination)
it began to fall over, as now there were two routes to retrieving data.

Having two methods for presenting data felt like an unnecessary cognitive overhead.

## Svello
Having seen svelte mentioned a few times over the last few years and I finally
decided to give the tutorial a go and was pleasantly surprised.

Although the features themselves aren't exactly game changing (their reduction
in boilerplate is probably my favourite), the new approach that it led me to
greatly improved my prototyping time.

Previously I would extract actions (i.e. calling an API) in to a redux store,
the result would then be reduced in to a state and the state would be readable
via selectors. Actions would be dispatched from display components and read via
selectors. Simple stuff.

Except that is a lot of boilerplate for a page that is retrieving data that is
only accessible on one page. Of course I could extract the API call out and add
it to the display component, but then I lose the ability to have that data
easily accessible from other components that might want to write to it.

An easy example would be `DisplayData` and `CreateData` components. `Display` does
not care about adding data on to this field, it is only responsible for
displaying it and perhaps filtering it. `Create` does not care about what is
already available, but want's to be able to add to it. 

On paper this seems like a good opportunity to extract it all out in to a
`DataStore` which is able to manage all the logic, but after doing that many
times I really didn't appreciate having logic spread across several files.
Modifying always felt like a chore.

With svelte you are able to approach this in the following way:

```javascript
// stores.js
import { writable } from 'svelte/store'
export const dataStore = writable([])
```
Defining a store is an extremely trivial pursuit.

```javascript
// DisplayData
import { onMount } form 'svelte'
import { dataStore } from 'stores'

const getData = async () => {
	$dataStore = await fetchData()
}

// retrieve data when component mounts, or whenever we want
omMount(async () => await getData())

// display your data below
```
Having the logic for fetching data next to the logic for displaying it is
ideal.

```javascript
import { dataStore } from 'stores'

const getData = async () => {
	response = await createData(params...)
	dataStore.update(current => [...current, response])
}
// display your create data form
```
Logic for creating data should be extracted in to its own component, but needs
to be able to easily make the data accessible for other components reading it.

## Other bells and whistles
Some other features I like about svelte:

- Conditional templating; doing things like `{condition && <Component />}` or
  `{arr.map(e => fn(e))}` always felt like a hack in React. Having clear
  templating features makes for a more pleasant reading experience.
- Reduction in binding boilerplate; binding in React felt cumbersome: `<input
  onChange={e => setValue(e.target.value)} value={value} />` vs `<input
  bind:value />`
- Built in scoped styles.
- Built in transitions. Because shiny.
- Very quick! React is already pretty quick in most circumstances, but svelte
  feels quicker in the rewrite I made. This could of course be a placebo.

## Wishlist
The main wish (and I believe this is more an issue with my rollup config) is the
ability to compose styles from existing styles so I can reduce the class noise
in the HTML itself; I use tachyons which results in lots of class names and it
would be nice to mix it with the scoped styles to reduce that noise.

PostCSS has a `composes` functionality, but I couldn't get it to work in a
reasonable amount of time.
