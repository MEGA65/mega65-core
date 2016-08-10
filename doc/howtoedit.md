## This is the 'how to edit documentation' documentation file.

# Introduction  
We have decided to try and use the github '*.md' pages to document the design.  
The intention is to have the documentation in one place, close to the source, and always reflect the current build status.  

# What to document
Everything.  
At this stage we want to draw a line in the sand and document everything we know about the project. This includes:

1. how-to guides
1. how software is developed
1. how hardware is connected
1. how to use/develop
1. etc

# How to document  

1. git uses the markdown language, some online pages describing the format can be found here:  
https://help.github.com/articles/getting-started-with-writing-and-formatting-on-github/  
https://guides.github.com/features/mastering-markdown/
1. a suggested workflow for modifying/adding pages is:  
 1. clone the repo,  
 1. edit the .md file,  
 1. view the rendered page in your browser using 'grip' (see below),  
 1. re-edit the .md file,  
 1. re-view the rendered page (and loop 4-5 until it looks nice),  
 1. commit the file locally and push to the repo.  

1. grip can be found here:  
https://github.com/joeyespo/grip  
 1. clone the repo
 1. cd into the base dir
 1. sudo python setup.py install
 1. sudo pip install grip
 1. cd to <mega65>/c65gs/doc
 1. grip index.md &
 1. in browser, goto http://localhost:6419/ where grip is rendering the index.md file
 1. killall grip

The End.
