## This is the 'how to contribute' documentation file.

# Introduction  
This page describes some etiquette and guidelines for contributing to this project.  
Can other developers please add to this file.

# Etiquette
Paul to define...

# How to make a branch  

Basically what I did was:
clone the repo and the default branch checked out on your local version is the MASTER branch.

```
dell960:~/dev$ git clone https://github.com/MEGA65/mega65-core.git
Cloning into 'mega65-core'...
remote: Counting objects: 10675, done.
remote: Compressing objects: 100% (3478/3478), done.
remote: Total 10675 (delta 7189), reused 10649 (delta 7163), pack-reused 0
Receiving objects: 100% (10675/10675), 15.73 MiB | 340.00 KiB/s, done.
Resolving deltas: 100% (7189/7189), done.
Checking connectivity... done.

dell960:~/dev$ git status
fatal: Not a git repository (or any parent up to mount point /home)
Stopping at filesystem boundary (GIT_DISCOVERY_ACROSS_FILESYSTEM not set).

dell960:~/dev$ cd mega65-core
dell960:~/dev/mega65-core$ git status
On branch master
Your branch is up-to-date with 'origin/master'.

dell960:~/dev/mega65-core$ git branch
* master

dell960:~/dev/mega65-core$ git pull
Already up-to-date.
```

I wanted to make a feature branch called 'sdcard' and so i did this through the github interface.
Yes I am already linked in as a contributor.
Because the 'sdcard' branch didnt exist, i was prompted to 'create'.
The github web-interface then showed that there was now a 'sdcard' branch.
Then on my local version, i did the following commands:

```
dell960:~/dev/mega65-core$ git pull
From https://github.com/MEGA65/mega65-core
 * [new branch]      sdcard     -> origin/sdcard
Already up-to-date.

dell960:~/dev/mega65-core$ git branch
* master
                    <- unsure why sdcard is not listed here until it is checked out

dell960:~/dev/mega65-core$ git checkout sdcard 
Branch sdcard set up to track remote branch sdcard from origin.
Switched to a new branch 'sdcard'

dell960:~/dev/mega65-core$ git branch
  master
* sdcard
```

So now I can happily go about developing in this feature-branch called 'sdcard'
without messing up the online 'master/default' branch that other people may clone.
Yes, if you clone the repo you get the 'master' branch AND the 'sdcard' branch, 
but by default the 'master' is checked out.
As shown below, its easy to switch between branches.

```
dell960:~/dev/mega65-core$ git checkout master
Switched to branch 'master'
Your branch is up-to-date with 'origin/master'.

dell960:~/dev/mega65-core$ git branch
* master
  sdcard
```

The End.
