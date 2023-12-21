#!/bin/sh

# change directory to the path of the script
cd "-bash"

# go to the src directory for Stockfish on my hard drive (edit accordingly)
cd ./chess/stockfish/src

echo
echo "This command will sync with master of official-stockfish"
echo

echo "Adding official Stockfish's public GitHub repository URL as a remote in my local git repository..."
git remote add     official https://github.com/official-stockfish/Stockfish.git
git remote set-url official https://github.com/official-stockfish/Stockfish.git

echo
echo "Going to my local master branch..."
git checkout master

echo
echo "Downloading official Stockfish's branches and commits..."
git fetch official

echo
echo "Updating my local master branch with the new commits from official Stockfish's master..."
git reset --hard official/master

echo
echo "Pushing my local master branch to my online GitHub repository..."
git push origin master --force

echo
echo "Compiling new master..."
make clean
make build -j
make net

echo
echo "Done."
