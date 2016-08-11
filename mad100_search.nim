#[#
========================================================================================
### Implementation of search functions:
### 1. MTD-bi search
### 2. Forced variation: search only for moves that leads to a capture for the opponent.
### 3. Normal alpha-beta search with aspiration windows
### Implementation of an opening book.
========================================================================================
#]#

from mad100
   import Position, parse_move, newPos, key, domove, rotate, eval_move, INITIAL_EXT
from mad100_utils
   import Move, null, isNull, rjust, MAX_NODES, WHITE, BLACK
from mad100_moves
   import matchMove, genMoves, hasCapture

import tables
import algorithm  # for sorting
from math import randomize, random
from sequtils import mapIt, apply
from strutils import intToStr, split
import os    # reading file
import pegs  # regular expression

# Constant TABLE_SIZE: maximum number allowed items in transposition table.
const TABLE_SIZE = 1000000

## The MATE_VALUE constant is the limit for stop searching
##   score <= -MATE_VALUE: player won
##   score >=  MATE_VALUE: player lost
## Theoretical the mate value must be greater than the maximum possible score
##
const MATE_VALUE* = 90000

###############################################################################
# MTD-bi search
###############################################################################

## GLOBALS
type Entry_tp* = tuple[tp_depth: int, tp_score: int, tp_gamma: int, tp_move: Move]
var entry: Entry_tp

var tp* = initTable[string, Entry_tp]()   # empty hash table with string as key
var nodes: int

proc arbKey[A, B](t: Table[A, B]): A =
   # Return an arbitrary key
   var arb_key: A
   for key in keys(t):
     arb_key = key   # break at first key
     break
   return arb_key
# end arbKey

proc bound(pos: Position, gamma: int, depth: int): int =
   # Alpha-beta pruning with null-window defined by gamma:
   # [alpha, beta] ~~ [gamma-1, gamma]
   # Parameter gamma is a guess of the exact score. It plays a role in a null-window search
   # with window [gamma-1, gamma]. Cut off childs if the real score >= gamma.
   #
   nodes += 1
   var entryFound: bool = false

   # Look in the tranposition table if we have already searched this position before.
   # We use the table value if it was done with at least as deep a search as ours,
   # and the gamma value is compatible.
   #

   if tp.hasKey(pos.key):
      entry = tp[pos.key]     # key is board string
      entryFound = true
      if depth <= entry.tp_depth and (
            (entry.tp_score < entry.tp_gamma and entry.tp_score < gamma) or
            (entry.tp_score >= entry.tp_gamma and entry.tp_score >= gamma) ):
         return entry.tp_score      # Use this score; stop searching this node

   # Stop searching if we have won/lost.
   if pos.score.abs >= MATE_VALUE:
      return pos.score

   # NULL MOVE HEURISTIC. For increasing speed.
   # The idea is that you give the opponent a free shot at you.
   # If your position is still so good that you exceed gamma, you assume
   # that you'd also exceed gamma if you went and searched all of your moves.
   # So you simply return gamma without searching any moves.
   #
   var nullswitch: bool = true    ### *** set ON/OFF *** ###
   let r = if (depth > 8): 3 else: 2              # depth reduction
   if depth >= 4 and not hasCapture(pos.board) and nullswitch:
      let child = pos.rotate()    # position of opponent without move of player
      let nullscore = -bound(child, 1-gamma, depth-1-r)     # RECURSION
      if nullscore >= gamma:
         return nullscore      # Nullscore high: stop searching this node

   # Evaluate or search further until end-leaves has no capture(s) (QUIESCENCE SEARCH)
   if depth <= 0 and not hasCapture(pos.board):
      return pos.score    # Evaluate position

   # We generate all possible legal moves and order them to provoke cuts.
   # At the next level of the tree we are going to minimize the score.
   # This can be shown equal to maximizing the negative score, with a slightly
   # adjusted gamma value.
   #
   var best = -MATE_VALUE
   var bmove = Move.null

   # Get moveList and sort it for faster result
   var moveList = genMoves(pos.board)
   moveList.apply(proc(m: Move): Move =  m.eval = pos.eval_move(m); return m )
   moveList.sort(proc (m1,m2: Move): int = cmp(m1.eval, m2.eval), Descending)

   for move in moveList:
      # Iterate over the sorted generator
      let score = -1 * bound(pos.domove(move), 1-gamma, depth-1)   # RECURSION
      if score > best:
         best = score
         bmove = move
      if score >= gamma: break   # CUT OFF

   # UPDATE TRANSPOSITION TABLE
   # We save the found move together with the score, so we can retrieve it in the play loop.
   # We also trim the transposition table. I prefer in FILO order. We use arbitrary key removal.
   # We prefer fail-high moves, as they are the ones we can build our PV (Principal Variation) from.
   # Depth condition: we prefer an entry with higher depth value.
   #    So replace the already retrieved entry if depth >= entry.depth
   #
   if entryFound == false or ( depth >= entry.tp_depth and best >= gamma ):
      let new_entry: Entry_tp = (depth, best, gamma, bmove)

      if tp.hasKey(pos.key): tp.del(pos.key)   ## tp.add should overwrite but seems to fail if not deleted
      tp.add(pos.key, new_entry )

      if tp.len > TABLE_SIZE:
         tp.del(tp.arbKey)    # removes an arbitrary (key,value) pair

   return best
# end bound

# forward declaration:
proc book_searchMove(pos: Position): Move

proc search*(pos: Position, maxn: int = MAX_NODES): tuple[move: Move, score: int] =
   # Iterative deepening MTD-bi search, the bisection search version of MTD
   # See the term "MTD-f" at wikipedia.

   let bookmove = book_searchMove(pos)
   if not bookmove.isNull:
      echo "Move from opening book"
      let new_entry: Entry_tp = (0, pos.score, 0, bookmove)
      if tp.hasKey(pos.key): tp.del(pos.key)   ## tp.add should overwrite but seems to fail if not deleted
      tp.add(pos.key, new_entry )
      if tp.len > TABLE_SIZE:
         tp.del(tp.arbKey)    # removes an arbitrary (key,value) pair
      return (move: bookmove, score: pos.score)

   nodes = 0
   if tp.len > (TABLE_SIZE div 2) :
      tp = initTable[string, Entry_tp]()     # empty hash table when half full

   echo "thinking ....   max nodes: " & $maxn
   echo "depth".rjust(8," ") & "nodes".rjust(8," ") &
        "gamma".rjust(8," ") & "score".rjust(8," ")  # header

   var score: int

   # We limit the depth to some constant, so we don't get a stack overflow in the end game.
   for depth in 1..99:
      # The inner loop is a binary search on the score of the position.
      # Inv: lower <= score <= upper
      # However this may be broken by values from the transposition table,
      # as they don't have the same concept of p(score). Hence we just use
      # 'lower < upper - margin' as the loop condition.
      var lower = -MATE_VALUE
      var upper =  MATE_VALUE
      var gamma: int
      while lower < (upper - 3):
         gamma = (lower+upper+1) div 2      # bisection !!   gamma === beta
         score = bound(pos, gamma, depth)   # AlphaBetaWithMemory

         #echo "GAMMA: d ", $depth,  " l " , $lower, " u " ,$upper,  " g ",$gamma, " s  ", $score

         if score >= gamma:
            lower = score
         if score < gamma:
            upper = score

      echo depth.intToStr.rjust(8," ") & nodes.intToStr.rjust(8," ") &
           gamma.intToStr.rjust(8," ") & score.intToStr.rjust(8," ")

      # We stop deepening if the global node counter shows we have spent
      # too long for this depth
      if nodes >= maxn: break

      # We stop deepening if we have already won/lost the game.
      if score.abs >= MATE_VALUE: break

   # We can retrieve our best move from the transposition table.
   if tp.hasKey(pos.key):
      entry = tp[pos.key]
      return (move: entry.tp_move, score: entry.tp_score)
   return (move: Move.null, score: score)       # move unknown
# end search

###############################################################################
# Search logic for Principal Variation Forced (PVF)
###############################################################################

type Entry_tpf* = tuple[tp_depth: int, tp_score: int, tp_move: Move]
var entry_tpf: Entry_tpf

var tpf* = initTable[string, Entry_tpf]()   # empty hash table with string as key
var xnodes: int

proc minimax_pvf(pos: Position, depth: int, player: int): int =
   # Fail soft negamax ab-pruning for forced principal variation
   # Parameter player: alternating +1 and -1 (player resp. opponent)
   # Test for dedicated problems shows: can be much faster than MTD-bi search
   xnodes += 1
   var entryFound: bool = false

   # Read transposition table
   if tpf.hasKey(pos.key):
      entry_tpf = tpf[pos.key]
      entryFound = true
      if depth <= entry_tpf.tp_depth:
         return entry_tpf.tp_score      # Stop searching this node

   # Evaluate or search further until end-leaves has no capture(s) (QUIESCENCE SEARCH)
   if depth <= 0 and not pos.board.hasCapture:
      return pos.score    # Evaluate position

   var best = -MATE_VALUE
   var bmove = Move.null
   var moveList = genMoves(pos.board)

   var mCount = 0
   for move in moveList:
      let child = pos.domove(move)

      if player == 0:
         if move.takes.len == 0 and not child.board.hasCapture:
            # Player decides only to look at moves that leads to a capture for the opponent.
            # But captures of the player are always inspected.
            continue

      if player == 1:
         if move.takes.len == 0:    # Inspect only captures for opponent
            continue

      # PRINT TREE
      ## echo "===".repeat(depth) & "> " & mrender_move(player, move)

      mCount += 1
      let score = -minimax_pvf(child, depth-1, 1-player)
      if score > best:
         best = score
         bmove = move
   # end moveList

   if mCount == 0:      # stop: no moves that leads to a capture for the opponent.
      return pos.score

   # Write transposition table
   if entryFound == false or depth >= entry_tpf.tp_depth:
      let new_entry: Entry_tpf = (depth, best, bmove)

      if tpf.hasKey(pos.key): tpf.del(pos.key)   ## tp.add should overwrite but seems to fail if not deleted
      tpf.add(pos.key, new_entry )

      if tpf.len > TABLE_SIZE:
         tpf.del(tpf.arbKey)    # removes an arbitrary (key,value) pair

   return best

proc search_pvf*(pos: Position, maxn: int = MAX_NODES): tuple[move: Move, score: int] =
   # Iterative deepening of forced variation sequence.
   xnodes = 0
   let player = 0            # 0 = starting player; 1 = opponent
   if tpf.len > (TABLE_SIZE div 2):
      tpf = initTable[string, Entry_tpf]()     # empty hash table when half full

   echo "thinking ....   max nodes: " & $maxn
   echo "depth".rjust(8," ") & "nodes".rjust(8," ") & "score".rjust(8," ")  # header

   var best: int = 0
   for depth in 1..99:
      best = minimax_pvf(pos, depth, player)

      ## REPORT
      echo depth.intToStr.rjust(8," ") & xnodes.intToStr.rjust(8," ") & best.intToStr.rjust(8," ")

      # We stop deepening if the global N counter shows we have spent too long for this depth
      if xnodes >= maxn: break

      # Looking for another stop criterium.
      # Sometimes a solution is found but search is going on until max nodes is reached.
      # We like to stop sooner and prevent waiting. But which stop citerium?

   # We can retrieve our best move from the transposition table.
   if tpf.hasKey(pos.key):
      entry_tpf = tpf[pos.key]
      return (move: entry_tpf.tp_move, score: best)
   return (move: Move.null, score: best)       # move unknown

# end search_pvf


###############################################################################
# Normal alpha-beta search with aspiration windows
###############################################################################

type Entry_tpab* = tuple[tp_depth: int, tp_score: int, tp_move: Move]
var entry_tpab: Entry_tpab

var tpab* = initTable[string, Entry_tpab]()  # empty hash table with string as key
var ynodes: int

proc alphabeta(pos: Position, alpha: int, beta: int, depthleft: int, player: int): int =
   # Fail soft: function returns value that may exceed its function call arguments.
   # Separate player code for better understanding.
   # Use of the transposition table tpab
   # TEST: uses 30-50% MORE nodes than MTD-bi search for getting the same result
   ynodes += 1
   var entryFound: bool = false

   # Read transposition table
   if tpab.hasKey(pos.key):
      entry_tpab = tpab[pos.key]
      entryFound = true
      if depthleft <= entry_tpab.tp_depth:
         return entry_tpab.tp_score      # Stop searching this node

   # Stop searching if we have won/lost.
   if pos.score.abs >= MATE_VALUE:
      return pos.score

   # NULL MOVE HEURISTIC. For increasing speed.
   # The idea is that you give the opponent a free shot at you.
   # If your position is still so good that you exceed beta, you assume
   # that you'd also exceed beta if you went and searched all of your moves.
   # So you simply return beta without searching any moves.
   #
   var nullswitch: bool = true    ### *** set ON/OFF *** ###
   let r = if (depthleft > 8): 3 else: 2              # depth reduction
   if depthleft >= 4 and not hasCapture(pos.board) and nullswitch:
      let child = pos.rotate()    # position of opponent without move of player
      let nullscore = alphabeta(child, alpha, alpha+1, depthleft-1-r, 1-player)   # RECURSION
      if player == 0:
         if nullscore >= beta: return beta    # Nullscore high: stop searching this node
      if player == 1:
         if nullscore <= alpha: return alpha  # Nullscore low: stop searching this node

   var bestValue: int
   var bestMove: Move

   # Get moveList and sort it for faster result
   var moveList = genMoves(pos.board)
   moveList.apply(proc(m: Move): Move =  m.eval = pos.eval_move(m); return m )
   moveList.sort(proc (m1,m2: Move): int = cmp(m1.eval, m2.eval), Descending)

   if player == 0:
      # Evaluate or search further until end-leaves has no capture(s) (QUIESCENCE SEARCH)
      if depthleft <= 0 and (not pos.board.hasCapture):
         return pos.score    # Evaluate position

      bestValue = -MATE_VALUE
      bestMove = Move.null
      var alphaMax = alpha        # clone of alpha (we do not want to change input parameter)
      for move in moveList:
         let child = pos.domove(move)
         let score = alphabeta(child, alphaMax, beta, depthleft-1, 1-player)   # RECURSION
         if score > bestValue:
            bestValue = score           # bestValue is running max of score
            bestMove = move
         alphaMax = alphaMax.max(bestValue)  # alphaMax is running max of alpha
         if alphaMax >= beta: break          # beta cut-off

   if player == 1:
      # Evaluate or search further until end-leaves has no capture(s) (QUIESCENCE SEARCH)
      if depthleft <= 0 and (not pos.board.hasCapture):
         return -1 * pos.score    # Evaluate position

      bestValue = MATE_VALUE
      bestMove = Move.null
      var betaMin = beta          # clone of beta

      for move in moveList:
         let child = pos.domove(move)
         let score = alphabeta(child, alpha, betaMin, depthleft-1, 1-player)   # RECURSION
         if score < bestValue:
            bestValue = score           # bestValue is running min of score
            bestMove = move
         betaMin = betaMin.min(bestValue)    # betaMin is running min of beta
         if betaMin <= alpha: break          # alpha cut-off

   # Write transposition table
   if entryFound == false or depthleft >= entry_tpab.tp_depth:
      let new_entry: Entry_tpab = (depthleft, bestValue, bestMove)

      if tpab.hasKey(pos.key): tpab.del(pos.key)   ## tpab.add should overwrite but seems to fail if not deleted
      tpab.add(pos.key, new_entry )

      if tpab.len > TABLE_SIZE:
         tpab.del(tpab.arbKey)    # removes an arbitrary (key,value) pair

   return bestValue
# end alphabeta


proc search_ab*(pos: Position, maxn: int = MAX_NODES): tuple[move: Move, score: int] =
   # Iterative deepening alpha-beta search enhanced with aspiration windows
   ynodes = 0
   if tpab.len > (TABLE_SIZE div 2) :
      tpab = initTable[string, Entry_tpab]()     # empty hash table when half full

   echo "thinking ....   max nodes: " & $maxn
   echo "depth".rjust(8," ") & "nodes".rjust(8," ") &
        "score".rjust(8," ") & "alpha".rjust(8," ") &
        "beta".rjust(8," ") # header

   var lower = -MATE_VALUE
   var upper =  MATE_VALUE
   let valWINDOW = 50         # ASPIRATION WINDOW: tune for optimal results

   # We limit the depth to some constant, so we don't get a stack overflow
   # in the end game.
   var alpha = lower
   var beta =  upper
   var depthleft = 1
   var score: int = 0
   while depthleft < 100:
      let player = 0            # 0 = starting player is max; 1 = opponent
      score = alphabeta(pos, alpha, beta, depthleft, player)

      ## REPORT
      echo depthleft.intToStr.rjust(8," ") & ynodes.intToStr.rjust(8," ") &
           score.intToStr.rjust(8," ") &
           alpha.intToStr.rjust(8," ") & beta.intToStr.rjust(8," ")

      # We stop deepening if the global N counter shows we have spent too
      # long for this depth
      if ynodes >= maxn: break

      # We stop deepening if we have already won/lost the game.
      if score.abs >= MATE_VALUE: break

      if score <= alpha or score >= beta:
         alpha = lower
         beta =  upper
         continue   # sadly we must repeat with same depthleft

      alpha = score - valWINDOW
      beta =  score + valWINDOW
      depthleft += 1

   # We can retrieve our best move from the transposition table.
   if tpab.hasKey(pos.key):
      entry_tpab = tpab[pos.key]
      return (move: entry_tpab.tp_move, score: entry_tpab.tp_score)
   return (move: Move.null, score: score)       # move unknown
# end search_ab


###############################################################################
# Logic Opening book
###############################################################################

#type Entry_open* = tuple[freq: int]
#var entry_open: Entry_open

var tp_open = initTable[string, int]()   # empty hash table with string as key

proc book_isPresent(f: string): bool =
   if existsFile f: return true
   return false

proc book_addEntry(pos: Position, move: Move): Position =
   # Do move and add entry for opening book to transposition table.
   let posnew = pos.domove(move)
   let key = posnew.key()
   if tp_open.hasKey(key):
      let freq = tp_open[key]
      tp_open[key] = freq + 1
   else:
      let freq = 1
      ##print('New entry:', move, freq)
      tp_open[key] = freq
   return posnew
# end book_addEntry

proc book_addLine(line: TaintedString): int =
   # Each line is an opening. Add entries to transposition table
   let pos_start: Position = newPos(INITIAL_EXT)  # starting position

   let line2 = line.replace(peg"[1-9]'.'", "")   # remove all move numbers
   let smoves = line2.split

   ##print('add new opening')
   var pos = pos_start
   var color = WHITE
   var movecount = 0
   for smove in smoves:
      let nsteps = parse_move(smove)     # module 'mad100'
      let nsteps2 = if color == WHITE: nsteps else: nsteps.mapIt(51 - it)

      let move = matchMove(pos.board, nsteps2)
      if move.isNull:
         echo "Illegal move in opening book; move " & smove & " in " & line
         break

      pos = book_addEntry(pos, move)  # update pos with move
      color = 1 - color      # alternating 0 and 1 (WHITE and BLACK)
      movecount += 1
   return movecount
# end book_addLine

proc book_readFile*(fs: string): void =
   # Read opening book
   if not book_isPresent(fs):
      echo "Opening book not available: " & fs
      return    # no opening book found

   echo "Reading opening book " & fs & " ...."
   tp_open = initTable[string, int]()     # init/reset transposition table as global

   let file = fs.open(fmRead)
   var linecount = 0
   var movecount = 0
   var line: TaintedString = ""
   while file.readLine(line):
      linecount += 1
      #line = line.chomp.strip
      #if line[0] != '#':      break
      let count = book_addLine(line)
      movecount += count
      #echo line

   file.close
   echo "Opening book read: " & $linecount & " lines and " & $movecount & " positions"
# end book_readFile

proc book_searchMove(pos: Position): Move =
   # Returns a move from pos which results in a position from the opening book
   type Entry_cand = tuple[move: Move, freq: int]
   var entry_cand: Entry_cand
   var candidates: seq[Entry_cand] = @[]      # sequence of candidate moves

   var moveList = genMoves(pos.board)
   for move in moveList:
      let posnew = pos.domove(move)
      if tp_open.hasKey(posnew.key):
         let freq = tp_open[posnew.key]
         ##print('move:', move)
         entry_cand = (move, freq)
         candidates.add entry_cand

   if candidates.len == 0:
      return Move.null
   if candidates.len == 1:
      return candidates[0].move

   candidates.sort(proc (e1,e2: Entry_cand): int = cmp(e1.freq, e2.freq), Descending)
   # Two strategies to select one candidate move
   # 1. Select move with highest frequence
   # 2. Select a random candidate move
   var sel_move: Move = Move.null
   let s = 1       # which choice

   if s == 0:
      let high_i = 0     # highest freq after sort
      sel_move = candidates[high_i].move
      ##puts 'candidate highest freq: ' candidates[high_i].move.inspect + ' ' + candidates[high_i].freq.inspect

   if s == 1:
      randomize()
      let rand_i = random(0..candidates.high)   # random index
      sel_move = candidates[rand_i].move
      ##echo "random candidate: " sel_move & ' ' & $candidates[rand_i].freq

   return sel_move
# end book_searchMove

#===================================================================
proc clearSearchTables*(): void =
   # Reset search tables to initial state (not tp_open)
   var compiled: bool = false
   when compiles(tp.clear):
      tp.clear()   ## Compile error in old versions of module tables.nim
      compiled = true
   when compiles(tpf.clear):
      tpf.clear()   ## Compile error in old versions of module tables.nim
      compiled = true
   when compiles(tpab.clear):
      tpab.clear()   ## Compile error in old versions of module tables.nim
      compiled = true
   if not compiled:
      echo "Warning: routine clear in module tables.nim can not compiled"
   return
# end clearSearchTables

#===================================================================
when isMainModule:
   # Test
   echo()
   echo "<<< Only for test; try mad100_run.nim >>> "
   echo()

###############################################################################
