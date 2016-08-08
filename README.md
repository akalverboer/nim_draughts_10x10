
MAD100.nim
=========
MAD100.nim is a simple, but strong draughts engine, written in Nim, mostly for teaching purposes.
It supports the international rules of 10x10 boards.

The clarity of the MAD100.nim code provides a great platform for experimenting, be it with evaluation functions, search extensions or anything. Fork it today and see what you can do!

Screenshot
==========

![MAD100 in action](images/mad100_in_action1.png)

Run it!
=======
MAD100.nim is contained in six Nim source files:  
- mad100_run.nim
- mad100.nim
- mad100_moves.nim 
- mad100_search.nim 
- mad100_play.nim  
- mad100_utils.nim  

I compiled the source code with Nim Compiler Version 0.13.0 (2016-05-19) [Linux: i386]
Compile it with the command: *nim c -d:release mad100_run.nim*  
Run the executable from the commandline with: *./mad100_run*  
Answer with the command **h** for help.  

Features
========
1. Built around the simple, but deadly efficient MTD-bi search algorithm.
2. Filled with game programming tricks for simpler and faster code.
3. Easily adaptive evaluation function through Piece Square Tables.
4. Uses standard Nim collections and data structures for clarity and efficiency.

Limitations
===========
All input and output is done with the commandline.
Moves must be given in simple move notation, as shown in the screenshot.

The evaluation in MAD100.nim is not very sophisticated. E.g. we don't distinguish between midgame and endgame. Not much selective deepening is done, no threat detection and the like. Finally MAD100.nim might benefit from a more advanced move ordering, including such things as killer move.

Why MAD100?
===========
The name MAD refers to the reverse of DAM: the dutch name for the king of draughts. 
The number refers to the 100 squares of the board.
By the way: for Nim programmers it is not difficult to convert it to a 64 squares version.

Tags
====
draughts engine, Nim language, MTD-bi search, alpha-beta pruning, fail soft, negamax, aspiration windows, null move heuristic,  opening book, quiescence search, iterative deepening, transposition table, principal variation, evaluation, piece square tables, FEN

Links
=====
- [Nim website](http://nim-lang.org/)
- [Chess programming](https://chessprogramming.wikispaces.com/)
- [Wikipedia draughts](https://en.wikipedia.org/wiki/International_draughts)

