#[#
###=====================================================================================
### Module methods for playing a game
###=====================================================================================
#]#

from strutils import split, parseInt, toLower, toUpper, replace, repeat, join
from sequtils import mapIt
from tables  import toTable, `[]`, `$`         # hash, dict
import pegs                                    # regular expressions
import tables, sets

from mad100_utils
   import toSeq
from mad100_search
   import tp, Entry_tp
from mad100
   import Position, clone, key, eval_pos, rotate, parse_move, render_move, print_pos
from mad100_utils
   import mapIt, Move, null, isNull, WHITE, BLACK


# FEN examples
const FEN_INITIAL: string =
   "W:B1-20:W31-50"
const FEN_MAD100_1: string =
   "W:W15,19,24,29,32,41,49,50:B5,8,30,35,37,40,42,45.Lauwen1977"  # P.Lauwen, DP, 4/1977
const FEN_MAD100_2: string =
   "W:W17,28,32,33,38,41,43:B10,18-20,23,24,37."
const FEN_MAD100_3: string =
   "W:WK3,25,34,45:B38,K47."
const FEN_MAD100_4: string =
   "W:W18,23,31,33,34,39,47:B8,11,20,24,25,26,32.xxx"       # M.Dalman
const FEN_MAD100_5: string =
   "B:B7,11,13,17,20,22,24,30,41:W26,28,29,31,32,33,38,40,48."  # after 30-35 white wins

# Solution 1x1 after 20 moves!! Mad100 finds solution. Set nodes 300000.
const FEN_MAD100_6: string =
   "W:W16,21,25,32,37,38,41,42,45,46,49,50:B8,9,12,17,18,19,26,29,30,33,34,35,36."


proc parseFEN*(iFen: string): Position =
   # Parses a string in Forsyth-Edwards Notation into a Position
   var fen = iFen                        # working copy
   fen = fen.replace(" ", "")            # remove all whitespace
   fen = fen.replace(peg"\..*$", "")     # cut off info (.xxx) at the end
   fen = if fen == "":    "W:B:W" else: fen          # empty FEN Position
   fen = if fen == "W::": "W:B:W" else: fen
   fen = if fen == "B::": "B:B:W" else: fen

   fen = fen.replace(peg".?'::'$", "W:W:B")
   ###echo "FEN2: ", fen

   let parts = fen.split(":")
   var rlist: string = '0'.repeat(51)       # init return string

   let sideToMove = if parts[0][0] == 'B': 'B' else: 'W'
   rlist[0] = sideToMove

   for i in 1..2:         # skip first, process the two sides
      var side = parts[i]                # working copy
      let color = side[0]                # first char
      side = side[1..side.high]          # strip first color char
      if side.len == 0:                  # nothing to do: next side
         continue

      let numSquares = side.split(",")   # list of numbers or range of numbers with/without king flag
      for item in numSquares:
         let isKing = if item[0] == 'K': true else: false
         let num = if isKing: item[1..item.high] else: item        # strip 'K'

         let isRange = if (num.split("-").len == 2): true else: false
         if isRange:
            let r = num.split("-")
            for j in  parseInt(r[0]) .. parseInt(r[1]):
               rlist[j] = if isKing: color.toUpper else: color.toLower
         else:
            rlist[parseInt(num)] = if isKing: color.toUpper else: color.toLower
   # for two sides

   # prepare output
   let pcode = {'w' : 'P', 'W' : 'K', 'b' : 'p', 'B' : 'k', '0' : '.'}.toTable
   var board: array[52, char]
   var sq = newSeq[char](50)
   sq = rlist[1..rlist.high].mapIt(pcode[it]).toSeq
   board[0] = '0'
   board[51] = '0'
   for i, p in sq: board[i+1] = p

   var pos = Position(board: board, score: 0)   # module 'mad100'
   pos.score = pos.eval_pos()
   return ( if sideToMove == 'W': pos else: pos.rotate )

# parseFEN =====================================================================

proc mrender_move*(color: int, move: Move): string =
   # Render move to string in numeric format: (m)utual version
   if move.isNull: return ""

   let steps = if color == WHITE: move.steps else: move.steps.mapIt(51-it)
   let takes = if color == WHITE: move.takes else: move.takes.mapIt(51-it)
   let rmove = Move(steps: steps, takes: takes, eval: 0)
   return render_move(rmove)           # module 'mad100'

proc mparse_move*(color: int, move: string): seq[int] =
   # Parameter move in numeric format like 17-14 or 10x17.
   # Return list of steps of move/capture in number format depending on color.
   let nsteps = parse_move(move)     # module 'mad100'
   return ( if color == WHITE: nsteps else: nsteps.mapIt(51 - it) )

proc mprint_pos*(color: int, pos: Position): void =
   # Print position depending on color
   if color == WHITE:
      print_pos(pos)           # module 'mad100'
   else:
      print_pos(pos.rotate())  # module 'mad100'
   let pcolor = @["white", "black"]
   echo pcolor[color] & " to move "


# Entry for saving principal variation moves
type Entry_pv* = tuple[pv_position: Position, pv_score: int, pv_move: Move]


proc gen_pv*[B](pos: Position, tp: Table[string, B]): auto =
   # Returns generator of principal variation list of scores and moves from transposition table
   var poskeys = initSet[string](4)  # init set of pos keys used to prevent loop
   var postemp = pos.clone()

   var entry: B   # default init: types Entry_tp, Entry_tpf, Entry_tpab
   result =
      iterator: Entry_pv =
         while true:
            var entryFound = false
            if tp.hasKey(postemp.key):
               entry = tp[postemp.key]  # get entry of transposition table
               entryFound = true
            if entryFound == false:
               break
            if poskeys.contains postemp.key:
               break    # Loop detected
            if entry.tp_move.isNull:
               let new_entry: Entry_pv = (postemp, entry.tp_score, entry.tp_move)
               yield new_entry
               break
            else:
               let new_entry: Entry_pv = (postemp, entry.tp_score, entry.tp_move)
               yield new_entry
               poskeys.incl(postemp.key)
               postemp = postemp.domove(entry.tp_move)
# gen_pv =====================================================================


proc render_pv*(origc: int, pv_list: seq[Entry_pv]): string =
   # Returns string of principal variation of scores and moves from pv_list
   var res: seq[string] = @[]
   var color = origc
   res.add "|"

   var last_score = 0
   for entry in pv_list:
      if entry.pv_move.isNull:
         res.add "null"
      else:
         let smove = mrender_move(color, entry.pv_move)
         res.add smove
         last_score = entry.pv_score
      res.add "|"
      color = 1 - color

   res.add " final score: "
   res.add $last_score
   return res.join(" ")
# render_pv =====================================================================


#===================================================================
when isMainModule:
   # Test
   echo()
   echo "<<< Only for test; try mad100_run.nim >>> "
   echo()

###############################################################################


