#!/bin/sh

#OBTAIN spider-monkey
sudo apt-get install mercurial autoconf2.13 –y
hg clone http://hg.mozilla.org/mozilla-central/ 
cd mozilla-central/js/src
autoconf2.13
./configure
make
sudo make install

# OBTAIN jsawk

sudo apt-get install curl -y
curl -L http://github.com/micha/jsawk/raw/master/jsawk > jsawk
sudo chmod 755 jsawk
touch ~/.jsawkrc
sudo mv jsawk /usr/bin/



echo | jsawk 'return "this works"'


