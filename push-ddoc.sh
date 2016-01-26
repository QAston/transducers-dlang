#!/bin/bash

 # Copyright (c) 2010-2011 Jakob Ovrum
 # Copyright (c) 2010-2011 Dariusz Antoniuk

 # Permission is hereby granted, free of charge, to any person
 # obtaining a copy of this software and associated documentation
 # files (the "Software"), to deal in the Software without
 # restriction, including without limitation the rights to use,
 # copy, modify, merge, publish, distribute, sublicense, and/or sell
 # copies of the Software, and to permit persons to whom the
 # Software is furnished to do so, subject to the following
 # conditions:

 # The above copyright notice and this permission notice shall be
 # included in all copies or substantial portions of the Software.

 # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 # EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 # OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 # NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 # HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 # WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 # FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 # OTHER DEALINGS IN THE SOFTWARE.


if [ "$TRAVIS_REPO_SLUG" == "QAston/transducers-dlang" ] && [ "$TRAVIS_PULL_REQUEST" == "false" ] && [ "$TRAVIS_BRANCH" == "master" ]; then
	git clone --recursive --branch=gh-pages https://github.com/${TRAVIS_REPO_SLUG}.git gh-pages

	cd gh-pages
	git config credential.helper "store --file=.git/credentials"
	echo "https://${GH_TOKEN}:@github.com" > .git/credentials
	git config --global user.name "travis-ci"
	git config --global user.email "travis@travis-ci.org"
	git config --global push.default simple

	echo -e "Generating DDoc...\n"
	sh ./generate.sh
	git add -f *.html
	git commit -m "Lastest documentation on successful travis build $TRAVIS_BUILD_NUMBER auto-pushed to gh-pages"
	git push
	echo -e "Published DDoc to gh-pages.\n"
fi