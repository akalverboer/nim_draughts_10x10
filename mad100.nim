# -*- coding: utf-8 -*-

#[#
###=====================================================================================
### MAD100 is a draughts engine for the 100 squares board.
### Inspired by the chess engine "Sunfish" of Thomas Ahle / Denmark.
### Capture rules same as International Draughts for a 10x10 board.
### Numeric representation of squares.

### This module implements the class Position, responsible for saving a board,
### moving a piece and evaluating a position.
### Includes printing a board and rendering a move.
###=====================================================================================
#]#

from strutils
   import split, parseInt, join, toUpper, isUpper,
          replace, intToStr, repeat, spaces
import pegs                                 # regular expressions
from tables  import toTable, `[]`, `$`      # hash, dict
from sequtils import mapIt                  # map

from mad100_utils import mapIt, seqToStr, toSeq, swapcase, Move, isNull, rjust


# The external respresentation of our board is a space delimited string for
# easy updating.
const INITIAL_EXT* =
    "   p   p   p   p   p "    &  #  01 - 05
    " p   p   p   p   p   "    &  #  06 - 10
    "   p   p   p   p   p "    &  #  11 - 15
    " p   p   p   p   p   "    &  #  16 - 20
    "   .   .   .   .   . "    &  #  21 - 25
    " .   .   .   .   .   "    &  #  26 - 30
    "   P   P   P   P   P "    &  #  31 - 35
    " P   P   P   P   P   "    &  #  36 - 40
    "   P   P   P   P   P "    &  #  41 - 45
    " P   P   P   P   P   "       #  46 - 50

const INITIAL_EXT_TEST* =
    "   .   K   .   .   . "    &  #  01 - 05
    " .   .   .   .   .   "    &  #  06 - 10
    "   p   .   k   .   . "    &  #  11 - 15
    " .   .   .   .   p   "    &  #  16 - 20
    "   .   .   .   .   p "    &  #  21 - 25
    " .   .   .   .   .   "    &  #  26 - 30
    "   .   p   .   .   . "    &  #  31 - 35
    " .   .   .   .   .   "    &  #  36 - 40
    "   P   .   .   p   . "    &  #  41 - 45
    " .   .   .   .   .   "       #  46 - 50

const INITIAL_EXT_TEST2* =
    "   .   .   .   .   . "    &  #  01 - 05
    " .   .   .   .   .   "    &  #  06 - 10
    "   p   .   .   .   . "    &  #  11 - 15
    " .   .   p   p   p   "    &  #  16 - 20
    "   .   .   .   .   p "    &  #  21 - 25
    " .   .   p   .   .   "    &  #  26 - 30
    "   .   K   .   p   . "    &  #  31 - 35
    " .   .   .   .   .   "    &  #  36 - 40
    "   .   .   .   .   K "    &  #  41 - 45
    " .   .   .   .   .   "       #  46 - 50

const INITIAL_EXT_PROBLEM1* =
    "   .   .   .   .   p "    &  #  01 - 05  P.Lauwen, DP, 4/1977
    " .   .   p   .   .   "    &  #  06 - 10
    "   .   .   .   .   P "    &  #  11 - 15
    " .   .   .   P   .   "    &  #  16 - 20
    "   .   .   .   P   . "    &  #  21 - 25
    " .   .   .   P   p   "    &  #  26 - 30
    "   .   P   .   .   p "    &  #  31 - 35
    " .   p   .   .   p   "    &  #  36 - 40
    "   P   p   .   .   p "    &  #  41 - 45
    " .   .   .   P   P   "       #  46 - 50

###############################################################################
# Evaluation tables
###############################################################################

# Piece Score Table (PST, External Representation) for piece ('P') and king ('K')
# Because of symmetry the PST is only given for white (uppercase letter)
# Material value for one piece is 1000.

const pst_ext = {
  'P':  "    000   000   000   000   000 "    & #  01 - 05   PIECE promotion line
        " 045   050   055   050   045    "    & #  06 - 10
        "    040   045   050   045   040 "    & #  11 - 15
        " 035   040   045   040   035    "    & #  16 - 20
        "    025   030   030   025   030 "    & #  21 - 25   Small threshold to prevent to optimistic behaviour
        " 025   030   035   030   025    "    & #  26 - 30
        "    020   025   030   020   025 "    & #  31 - 35
        " 020   015   025   020   015    "    & #  36 - 40
        "    010   015   020   010   015 "    & #  41 - 45
        " 005   010   015   010   005    ",     #  46 - 50
  'K':  "    050   050   050   050   050 "    & #  01 - 05
        " 050   050   050   050   050    "    & #  06 - 10
        "    050   050   050   050   050 "    & #  11 - 15
        " 050   050   050   050   050    "    & #  16 - 20
        "    050   050   050   050   050 "    & #  21 - 25
        " 050   050   050   050   050    "    & #  26 - 30
        "    050   050   050   050   050 "    & #  31 - 35
        " 050   050   050   050   050    "    & #  36 - 40
        "    050   050   050   050   050 "    & #  41 - 45
        " 050   050   050   050   050    "      #  46 - 50
}.toTable

# Internal representation of PST with zeros at begin and end (rotation-symmetry)
const PST_P: seq[int] = @[0] & pst_ext['P'].split.mapIt(parseInt(it)) & @[0]
const PST_K: seq[int] = @[0] & pst_ext['K'].split.mapIt(parseInt(it)) & @[0]
const PST = {'P': PST_P , 'K': PST_K}.toTable
const PMAT = {'P': 1000, 'K': 3000}.toTable

###############################################################################
# Draughts logic
###############################################################################

type
   Position* = ref object of RootObj
      # A state of a draughts100 game
      # - board: sequence of 52 char; filled with 'p', 'P', 'k', 'K', '.' and '0'
      #   first and last index unused ('0') rotation-symmetry
      # - score: the board evaluation
      #
      board*: seq[char]    # length 52 char
      score*: int


proc key*(pos: Position): string {.inline.} =
   # Define a good hash key
   var posKey: string = pos.board.seqToStr
   return posKey

proc rotateBoard(board: seq[char]): seq[char] =
   # Create new position with reversed board and items swapped.
   var rotBoard = newSeq[char](board.len)
   for i, c in board:
      rotBoard[board.high - i] = c.swapcase
   return rotBoard

proc rotate*(pos: Position): Position  {.inline.} =
   # Create new position with reversed board and items swapped; reverse the score
   let rotBoard: seq[char] = pos.board.rotateBoard
   return Position(board: rotBoard, score: -1 * pos.score)

proc clone*(pos: Position): Position  {.inline.} =
   return Position(board: pos.board, score: pos.score)


proc eval_move*(pos: Position, move: Move): int =
   # Returns increment of board score by this move (neg or pos)
   # Simulate the move and compute increment of the score
   let i = move.steps[0]
   let j = move.steps[move.steps.high]    # last (NB. sometimes i==j !)
   let p = pos.board[i]

   # Actual move: increment of score by move
   let promotion_line = 1..5
   var score: int
   if (j in promotion_line) and (p != 'K'):
      let from_val = PST[p][i] + PMAT[p]
      let to_val = PST['K'][j] + PMAT['K']    # piece promoted to king
      score = to_val - from_val
   else:
      let from_val = PST[p][i] + PMAT[p]
      let to_val = PST[p][j] + PMAT[p]
      score = to_val - from_val

   # Increase of score because of captured pieces
   for i, val in move.takes:
      let q = pos.board[val].toUpper
      score += PST[q][51-val] + PMAT[q]   # score from perspective of other player
   return score


proc eval_pos*(pos: Position): int  {.inline.} =
   # Computes the board score and returns it
   var score1: int = 0
   for i, p in pos.board:
      if p.isUpper:         # p == 'P' or p == 'K'
         score1 = score1 + PMAT[p] + PST[p][i]

   let rotBoard: seq[char] = pos.board.rotateBoard   # we want score of opponent
   var score2: int = 0
   for i, p in rotBoard:
      if p.isUpper:         # p == 'P' or p == 'K'
         score2 = score2 + PMAT[p] + PST[p][i]

   let score: int = score1 - score2
   ##echo("Total score: ", score, score1, score2)
   return score


proc domove*(pos: Position, move: Move): Position =
   # Move is named tuple with list of steps and list of takes
   # Returns new rotated position object after moving.
   # Calculates the score of the returned position.
   # Remember: move is always done with white

   if move.isNull:
      return pos.rotate     # turn to other player

   var board = pos.board        # clone board
   # Actual move
   let i = move.steps[0]
   let j = move.steps[move.steps.high]    # last (NB. sometimes i==j !)
   let p = board[i]

   # Move piece and promote to white king
   let promotion_line = 1..5
   board[i] = '.'
   if (j in promotion_line) and (p != 'K'):
      board[j] = 'K'
   else:
      board[j] = p

   # Capture
   for i, val in move.takes: board[val] = '.'

   # We increment the score of the new position depending on the move.
   var score = pos.score + pos.eval_move(move)

   # The incremental update of the score depending on the move is not always
   # possible for evaluation measures like mobility, patterns, etc.
   # If needed we can re-compute the score of the whole position by:
   #      posnew.score = posnew.eval_pos()
   # The incremental update depending on the move is much faster.

   # We rotate the returned position, so it's ready for the next player
   let posnew = Position(board: board, score: score).rotate()
   return posnew

#===========================================================================

proc newPos*(iBoard: string): Position  {.inline.} =
   # Return position object based on external representation of board (string)
   let board = @['0'] & iBoard.replace(" ","").toSeq & @['0']
   let pos = Position(board: board, score: 0)
   pos.score = pos.eval_pos
   return pos


###############################################################################
# User interface
###############################################################################

proc parse_move*(move: string): seq[int] =
   # Parameter move in numeric format like "32-28" or "26x37".
   # Return array of steps of move/capture in number format.
   let nsteps = move.split(peg"[-x]").mapIt it.parseInt
   return nsteps


proc render_move*(move: Move): string =
   # Parameter move in tuple format. Render move in numeric format
   let d = if (move.takes.len == 0): "-" else: "x"
   let last = move.steps.high
   return move.steps[0].intToStr & d & move.steps[last].intToStr


proc print_pos*(pos: Position): void  {.inline.} =
   # ⛀    ⛁    ⛂    ⛃
   # board is array 0..52; filled with 'p', 'P', 'k', 'K', '.' and '0'
   echo()
   var spaces: int = 0
   let uni_pieces =
      {'p' : "⛂", 'k' : "⛃", 'P' : "⛀", 'K' : "⛁", '.' : "·", ' ' : " "}.toTable
   let nrows = 10
   let row_len = 5   # nrows.div 2
   var mapped: seq[string]
   for i in 1..nrows:
      let start = (i-1) * row_len + 1
      let row = pos.board[start..start + row_len - 1]
      spaces = if spaces == 2: 0 else: 2    # alternating

      mapped = @[]
      for ch in row: mapped.add  uni_pieces[ch]
      let s_from = start.intToStr.rjust(2,"0")
      let s_to = (start + row_len - 1).intToStr.rjust(2,"0")
      echo s_from & "-"  &  s_to  &  "   "  &  " ".repeat(spaces)  &
           mapped.join("   ")
   echo()
   return

#===================================================================
when isMainModule:
   # Test
   echo()
   echo "<<< Only for test; try mad100_run.nim >>> "
   echo()

###############################################################################

