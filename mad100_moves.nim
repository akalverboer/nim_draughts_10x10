#[# =================================================================================
###   Move logic for Draughts 100 International Rules
###
###   Remember:
###   - The internal respresentation of our board is a string of 52 char
###   - Moves are always calculated for white (uppercase letters) at high numbers!!
###   - If black is to move, black and white are swapped and the board is rotated.
###
###   Directions: external representation for easy updating.
###   Tables give for each square the next square depending on a direction (NE, NW, SE, SW)
#]#

from strutils import split, isUpper, isLower, intToStr
from sequtils import filterIt
from tables import initTable,len ,add, hasKey, Table, keys, del, `[]`
import sets      # using toSet; error if "from sets import toSet"

from mad100_utils import Move, null, isNull, seqToStr

# Directions: four constant arrays of square numbers.
# For example, first square from i in direction NE is NE[i]

const NE: array[52, int] =
     [0,                          # 0 at start
        00, 00, 00, 00, 00,       #  01 - 05
      01, 02, 03, 04, 05,         #  06 - 10
        07, 08, 09, 10, 00,       #  11 - 15
      11, 12, 13, 14, 15,         #  16 - 20
        17, 18, 19, 20, 00,       #  21 - 25
      21, 22, 23, 24, 25,         #  26 - 30
        27, 28, 29, 30, 00,       #  31 - 35
      31, 32, 33, 34, 35,         #  36 - 40
        37, 38, 39, 40, 00,       #  41 - 45
      41, 42, 43, 44, 45,         #  46 - 50
     0]                           # 0 at end

const NW: array[52, int] =
     [0,                          # 0 at start
       00, 00, 00, 00, 00,        # 01 - 05
     00, 01, 02, 03, 04,          # 06 - 10
       06, 07, 08, 09, 10,        # 11 - 15
     00, 11, 12, 13, 14,          # 16 - 20
       16, 17, 18, 19, 20,        # 21 - 25
     00, 21, 22, 23, 24,          # 26 - 30
       26, 27, 28, 29, 30,        # 31 - 35
     00, 31, 32, 33, 34,          # 36 - 40
       36, 37, 38, 39, 40,        # 41 - 45
     00, 41, 42, 43, 44,          # 46 - 50
     0]                           # 0 at end

const SE: array[52, int] =
     [0,                          # 0 at start
       07, 08, 09, 10, 00,        # 01 - 05
     11, 12, 13, 14, 15,          # 06 - 10
       17, 18, 19, 20, 00,        # 11 - 15
     21, 22, 23, 24, 25,          # 16 - 20
       27, 28, 29, 30, 00,        # 21 - 25
     31, 32, 33, 34, 35,          # 26 - 30
       37, 38, 39, 40, 00,        # 31 - 35
     41, 42, 43, 44, 45,          # 36 - 40
       47, 48, 49, 50, 00,        # 41 - 45
     00, 00, 00, 00, 00,          # 46 - 50
     0]                           # 0 at end

const SW: array[52, int] =
     [0,                          # 0 at start
       06, 07, 08, 09, 10,        # 01 - 05
     00, 11, 12, 13, 14,          # 06 - 10
       16, 17, 18, 19, 20,        # 11 - 15
     00, 21, 22, 23, 24,          # 16 - 20
       26, 27, 28, 29, 30,        # 21 - 25
     00, 31, 32, 33, 34,          # 26 - 30
       36, 37, 38, 39, 40,        # 31 - 35
     00, 41, 42, 43, 44,          # 36 - 40
       46, 47, 48, 49, 50,        # 41 - 45
     00, 00, 00, 00, 00,          # 46 - 50
     0]                           # 0 at end

iterator diagonal(i: int, d: openarray[int]): int =
   # Generator for squares from i in direction d
   var nxt = i
   var stop = (d[nxt] == 0)
   while not(stop):
      nxt = d[nxt]
      stop = (d[nxt] == 0)
      yield nxt

const Directions = [NE, SE, SW, NW]

#----------------------------------------------------------------------
# We use a move table to remember the set of legal moves of a position
# for better performance.
#
var moveTable = initTable[string, seq[Move]]()
const TABLE_SIZE = 1000000

proc boardKey(board: openarray[char]): string =
   # Define a good hash key for moveTable
   var key: string = ""
   for c in board: key = key & c
   return key
# end boardKey

proc arbKey[A, B](t: Table[A, B]): A =
   # Return arbirary key for table t
   var arb_key: A
   for key in keys(t):
      arb_key = key   # break at first key
      break
   #echo "ARB_KEY: ", arb_key
   return arb_key
# end arbKey

proc clearMoveTable*() =         # PUBLIC
   # Clear moveTable
   moveTable = initTable[string, seq[Move]]()
# end clearMoveTable

proc moveTableSize*(): int =    # PUBLIC
   return moveTable.len
# end moveTableSize
#--------------------------------------------------------------------

proc bmoves_from_square*(board: openarray[char], i: int): seq[Move] =
   # List of moves (non-captures) for square i
   var moves: seq[Move] = @[]     # init output list; two moves
   let p = board[i]

   if not p.isUpper: return moves    # only moves for player; return empty sequence

   if p == 'P':
      for id in 0..3:
         let d = Directions[id]
         let q = board[d[i]]
         if q == '0' or q.isUpper: continue   # direction empty or own piece; try next direction
         if (q == '.') and (d[i] == NE[i] or d[i] == NW[i]):
            # move detected; save and continue
            moves.add Move(steps: @[i, d[i] ], takes: @[], eval: 0)

   if p == 'K':
      for id in 0..3:
         let d = Directions[id]
         for j in diagonal(i, d):  # diagonal squares from i in direction d
            let q = board[j]
            if q.isUpper: break    # own piece on this diagonal; stop
            if q == '0': break     # stay inside the board; stop with this diagonal
            if q != '.': break     # stop this direction if next square not empty
            if q == '.':
               # move detected; save and continue
               moves.add Move(steps: @[i,j], takes: @[], eval: 0)

   return moves
# end bmoves_from_square ======================================


proc bcaptures_from_square(board: openarray[char], i: int): seq[Move] =
   # List of one-take captures for square i
   var captures: seq[Move] = @[]     # init output list
   let p = board[i]

   if not p.isUpper:    # only captures for player; return empty list
      let res: seq[Move] = @[]
      return res

   if p == 'P':
      for id in 0..3:
         let d = Directions[id]
         let q = board[d[i]]
         if q == '0': continue        # stay inside the board; stop with this diagonal
         if q == '.' or q.isUpper: continue   # direction empty or own piece; try next direction

         if q.isLower:
            # try to find capture
            let r = board[ d[d[i]] ]  # second diagonal square
            if r == '0': continue     # no second diagonal square; try next direction
            if r == '.':
               # capture detected; save and continue
               captures.add Move(steps: @[ i, d[d[i]] ], takes: @[ d[i] ], eval: 0)

   if p == 'K':
      for id in 0..3:
         let d = Directions[id]
         var take: int = 0   # nil
         for j in diagonal(i, d):  # diagonal squares from i in direction d
            let q = board[j]
            if q.isUpper: break    # own piece on this diagonal; stop
            if q == '0': break     # stay inside the board; stop with this diagonal

            if q.isLower and take == 0:
               take = j      # square of q
               continue
            if q.isLower and take != 0: break
            if q == '.' and take != 0:
               # capture detected; save and continue
               captures.add Move(steps: @[i,j], takes: @[take], eval: 0)


   return captures
# end bcaptures_from_square ======================================


proc basicMoves(board: openarray[char]): seq[Move] =
   # Return list of basic moves of board; basic moves are normal moves (not captures)
   var bmoves_of_board: seq[Move] = @[]

   for i, p in board:
      if not p.isUpper: continue    # Upper: p == 'P' or p == 'K'
      bmoves_of_board = bmoves_of_board & bmoves_from_square(board, i)

   return bmoves_of_board
# end basicMoves

proc basicCaptures(board: openarray[char]): seq[Move] =
   # Return list of basic captures of board. Basic captures are one-take captures
   var bcaptures_of_board: seq[Move] = @[]

   for i, p in board:
      if not p.isUpper: continue    # Upper: p == 'P' or p == 'K'
      bcaptures_of_board = bcaptures_of_board & bcaptures_from_square(board, i)

   return bcaptures_of_board
# end basicCaptures



proc searchCaptures(board: array[52, char]): seq[Move] =
   # Capture construction by extending incomplete captures with basic captures
   var captures: seq[Move] = @[]       # result list of captures
   var max_takes: int = 0              # max number of taken pieces

   proc boundCaptures(board: array[52, char], capture: Move, depth: int ): void =
      # Recursive construction of captures. Update globals: captures and max_takes
      # - board: current board during capture construction
      # - capture: incomplete capture used to extend with basic captures
      # - depth: not used
      # Return value not used
      let from_square = capture.steps[capture.steps.high]
      let bcaptures = bcaptures_from_square(board, from_square)   # new extends of capture

      var completed: bool = true
      for bcapture in bcaptures:
         if bcapture.takes.len == 0: continue               # no capture; nothing to extend
         if bcapture.takes[0] in capture.takes: continue    # do not capture the same piece twice
         let n_from = bcapture.steps[0]
         let n_to = bcapture.steps[bcapture.steps.high]     # last step

         var new_board = board   # clone the board and do the capture without taking the piece
         new_board[n_from] = '.'
         new_board[n_to] = board[n_from]

         var new_capture = Move(steps: capture.steps, takes: capture.takes, eval: 0)  # make copy of move and extend it
         new_capture.steps.add  bcapture.steps[1]
         new_capture.takes.add  bcapture.takes[0]

         completed = false
         boundCaptures(new_board, new_capture, depth + 1)   # RECURSION

      if completed:
         # Update global variables
         captures.add  capture
         if capture.takes.len > max_takes:
            max_takes = capture.takes.len
      return
   # end boundCaptures

   # -----------------------------------------------------------------------------
   let depth = 0
   ###let bmoves = basicCaptures(board)
   for bmove in basicCaptures(board):
      # TO DO: RENAME bmove to bcapture
      let n_from = bmove.steps[0]
      let n_to = bmove.steps[bmove.steps.high]     # last step

      var new_board = board   # clone the board and do the capture without taking pieces
      new_board[n_from] = '.'
      new_board[n_to] = board[n_from]
      boundCaptures(new_board, bmove, depth)   # Search for captures

   result = captures.filterIt(it.takes.len == max_takes)
# end searchCaptures


proc hasCapture*(board: openarray[char]): bool =          # PUBLIC
   # Returns true if capture at board found for white else false.
   for i, p in board:
      if p.isUpper:    # Upper: p == 'P' or p == 'K'
         let bcaptures = bcaptures_from_square(board, i)
         if bcaptures.len > 0: return true
   return false
# end hasCapture


proc genMoves*(board: array[52, char]): seq[Move] =         # PUBLIC
   # Returns list of all legal moves of a board for player white (capital letters).
   # Move is a named tuple with array of steps and array of takes

   let bkey = boardKey(board)
   if moveTable.hasKey(bkey):
      # Use the already computed legal moves from the table
      let entry = moveTable[bkey]
      return entry

   var legalMoves: seq[Move] = @[]
   legalMoves = searchCaptures(board)
   if legalMoves.len == 0:
      legalMoves = basicMoves(board)

   # Update the moveTable so we need not compute legal moves for this board twice
   let new_entry: seq[Move] = legalMoves
   moveTable.add(bkey, new_entry )

   # We trim the transposition table. I prefer in FILO order but do not know
   # how NIM should do it. So we use arbitrary key removal.
   if moveTable.len > TABLE_SIZE:
      let aKey = moveTable.arbKey
      moveTable.del(aKey)

   return legalMoves
# end genMoves


proc isLegal*(board: array[52, char], move: Move): bool =        # PUBLIC
   # Returns true if move for position is legal else false.
   let legal_moves = genMoves(board)
   if move in legal_moves:
       ## echo "Illegal move: ", move.steps, move.takes
       return true
   return false
# isLegal ============================================


proc matchMove*(board: array[52, char], steps: seq[int]): Move =        # PUBLIC
   # Match array of steps with a legal move. Return matched move or nilMove

   var lmoves = genMoves(board)   # legal moves

   if steps.len == 2:
      for move in lmoves:
         if move.steps[0] == steps[0] and
            move.steps[move.steps.high] == steps[steps.high]:
            return move
   else:
      for move in lmoves:
         if move.steps.toSet == steps.toSet:
            return move

   return Move.null
# end  match_move


#======================================================================
when isMainModule:
   # Test
   echo()
   echo "<<< Only for test; try mad100_run.nim >>> "
   echo()

   # TEST 1 (diagonal iterator)
   #for i in diagonal(32, NE):
   #   stdout.write $i & "  "
   #stdout.write "\n"


#######################################################################


