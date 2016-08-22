#[#
========================================================================================
###   MAD100 is a draughts engine for the 100 squares board.
###   This module implements the user interface for running MAD100.
========================================================================================
#]#

from strutils import startsWith, strip, split, parseInt    # string utils
import pegs                                      # regular expressions
import times, os

from mad100_search
   import search, search_pvf, search_ab, book_readFile, clearSearchTables, MATE_VALUE, tp, tpf, tpab
from mad100
   import Position, domove, newPos,
          INITIAL_EXT, INITIAL_EXT_TEST, INITIAL_EXT_TEST2, INITIAL_EXT_PROBLEM1
from mad100_moves
   import genMoves, hasCapture, moveTableSize, clearMoveTable, matchMove, isLegal
from mad100_play
   import Entry_pv, mparse_move, mrender_move, mprint_pos, parseFEN, gen_pv, render_pv
from mad100_utils
   import MAX_NODES, WHITE, BLACK, Move, null, isNull, toSeq


proc main(): void =
   # Main procedure
   echo("==========================================================")
   echo("| MAD100: Nim engine for draughts 100 international rules | ")
   echo("==========================================================")

   var max_nodes: int
   var color, origc: int
   var pos: Position
   var comm: string
   var stack: seq[string] = @[]
   stack.add "new"              # initial board
   stack.add "nodes 1000"       # initial level max_nodes
   var pntr: int = -1           # move pointer (ptr is nim-keyword)
   var pv_list: seq[Entry_pv] = @[]

   while true:
      if stack != @[]:
         comm = stack.pop
      else:
         stdout.write "Command: "
         comm = stdin.readLine.strip     # read input (without LF or CRLF)

      if comm.startsWith "q":
         echo("Bye")
         break
      elif comm.startsWith "legal":
         mprint_pos(color, pos)
         var lstring = ""
         var legalMoves = genMoves(pos.board)
         for lmove in legalMoves:
            lstring = lstring & mrender_move(color, lmove) & "  "
         echo "Legal moves: " & lstring

      elif comm.startsWith "nodes":
         # Set max_nodes to search
         if comm.split.len == 1:
            max_nodes = MAX_NODES  # DEFAULT
         elif comm.split.len >= 2:
            max_nodes = comm.split[1].parseInt
         echo "   Level max nodes: " & $max_nodes

      elif comm.startsWith "new":
         # Setup new position
         var board: string
         if comm.split.len == 1:
            board = INITIAL_EXT
         elif comm.split.len == 2:
            let choice = comm.split[1].parseInt
            if choice == 1: board = INITIAL_EXT_TEST
            if choice == 2: board = INITIAL_EXT_TEST2
            if choice == 3: board = INITIAL_EXT_PROBLEM1   # test problem solving

         pos = newPos(board)
         color = WHITE            # WHITE / BLACK

         clearSearchTables()     # reset transposition table
         clearMoveTable()
         mprint_pos(color, pos)

      elif comm.startsWith "fen":
         # setup position with fen string (!!! without apostrophes and no spaces !!!)
         if comm.split.len != 2: continue
         let fen = comm.split[1]
         pos = parseFEN(fen)     # module Play
         color = if fen[0] == 'B': BLACK else: WHITE

         clearSearchTables()     # reset transposition table
         clearMoveTable()
         mprint_pos(color, pos)
      elif comm.startsWith "eval":
         # Evaluate position
         mprint_pos(color, pos)
         echo "Score position: " & $pos.score

      elif comm.startsWith "go":
         # Search position for best move
         var move: Move
         var score: int
         #var res: tuple[move: Move, score: int]
         if comm.split.len == 1:
            # MTD-bi search for next move
            origc = color

            let t0 = cpuTime()
            let res = search(pos, max_nodes)
            move = res.move
            score = res.score
            let t1 =  cpuTime()
            echo "Time elapsed: ", $(t1 - t0)

            pv_list = gen_pv( pos, tp ).toSeq  # to array
            pntr = -1
            echo "Principal Variation: " & render_pv(origc, pv_list)
         elif comm.split.len == 2:
            let action = comm.split[1]
            if action == "f":
               # *** search for forced combinations ***
               origc = color
               let t0 = cpuTime()
               let res = search_pvf(pos, max_nodes)
               move = res.move
               score = res.score
               let t1 =  cpuTime()
               echo "Time elapsed: ", $(t1 - t0)

               pv_list = gen_pv( pos, tpf ).toSeq  # to array
               pntr = -1
               echo "Principal Variation: " & render_pv(origc, pv_list)
            elif action == "ab":
               # *** search with alpha-beta pruning ***
               origc = color
               let t0 = cpuTime()
               let res = search_ab(pos, max_nodes)
               move = res.move
               score = res.score

               let t1 =  cpuTime()
               echo "Time elapsed: ", $(t1 - t0)

               pv_list = gen_pv( pos, tpab ).toSeq  # to array
               pntr = -1
               echo "Principal Variation: " & render_pv(origc, pv_list)
            else:
               echo "Unknow action: " & action

         # We don't play well once we have detected our death
         if move.isNull:
            echo "no move found; score: " $score
         elif score >= MATE_VALUE:
            echo "very high score"
         elif score <= -MATE_VALUE:
            echo "very low score"
         else:
            let smove = mrender_move(color, move)
            echo "Best move: " & smove

      elif comm.startsWith("p"):
         if comm.split.len == 1:
            stack.add "pv >"    # do next move in PV
         elif comm.split.len == 2:
            let action = comm.split[1]
            if pv_list.len == 0:
               echo "No list of Principal Variation moves"
               continue
            if action == ">":
               # do next move in PV
               if pntr == (pv_list.len - 1):
                  echo "End of Principal Variation list"
                  continue
               pntr += 1
               let move = pv_list[pntr].pv_move
               if pos.board.isLegal(move):
                  echo "Move done: " & mrender_move(color, move)
                  pos = pos.domove(move)
                  color = 1 - color      # alternating 0 and 1 (WHITE and BLACK)
                  mprint_pos(color, pos)
               else:
                  pntr -= 1
                  echo "Illegal move; first run go"
            elif action == "<":
               # to previous position of PV
               if pntr < 0:
                  echo "Begin of Principal Variation list"
                  continue
               color = 1 - color
               pos = pv_list[pntr].pv_position
               mprint_pos(color, pos)
               pntr -= 1
            elif action == "<<":
               # reset starting position
               color = origc
               pntr = -1
               pos = pv_list[0].pv_position
               mprint_pos(color, pos)
            elif action == ">>":
               echo "not used: >>"

      elif comm.startsWith "m":
         if comm.split.len == 1:
            let t0 = cpuTime()
            let (move, score) = search(pos, max_nodes)
            let t1 =  cpuTime()
            echo "Time elapsed: ", $(t1 - t0)
            if move.isNull:
               echo "no move found; score: " $score
            elif score <= -MATE_VALUE:
               echo "very low score"
            elif score >= MATE_VALUE:
               echo "very high score"
            else:
               let pv_list = gen_pv( pos, tp ).toSeq  # to array
               echo "Principal Variation: " & render_pv(color, pv_list)
               echo "Move done: " & mrender_move(color, move)
               pos = pos.domove(move)
               color = 1 - color      # alternating 0 and 1 (WHITE and BLACK)
               mprint_pos(color, pos)
         elif comm.split.len == 2:
            var smove = comm.split[1]
            smove = smove.strip
            let m1 = smove.match(peg"^([0-9]+[-][0-9]+)$")      # move
            let m2 = smove.match(peg"^([0-9]+([x][0-9]+)+)$")   # capture
            if m1 or m2:
               let steps = mparse_move(color, smove)
               let lmove = matchMove(pos.board, steps)
               if pos.board.isLegal(lmove):
                  pos = pos.domove(lmove)
                  color = 1 - color      # alternating 0 and 1 (WHITE and BLACK)
                  mprint_pos(color, pos)
               else:
                  echo "Illegal move; please enter a legal move"
            else:
               # Inform the user when invalid input is entered
               echo "Please enter a move like 32-28 or 26x37"

      elif comm.startsWith "book":
         # *** init opening book ***
         let t0 =  cpuTime()
         #book_readFile("data/openbook_test15")
         book_readFile("data/mad100_openbook")
         let t1 =  cpuTime()
         echo "Time elapsed: ", $(t1 - t0)

      elif comm.find(peg"^[hH\?]") > -1:   # startswith h, H or ?
         echo(" _________________________________________________________________ ")
         echo("| Use one of these commands: ")
         echo("| ")
         echo("| q:           quit ")
         echo("| h:           this help info ")
         echo("| new:         setup initial position ")
         echo("| fen <fen>:   setup position with fen-string ")
         echo("| eval:        print score of position ")
         echo("| legal:       show legal moves ")
         echo("| nodes <num>: set max number of nodes for search (or default) ")
         echo("| ")
         echo("| m       : let computer search and play a move ")
         echo("| m <move>: do move (format: 32-28, 16x27, etc) ")
         echo("| ")
         echo("| p       : do moves of PV (principal variation) ")
         echo("|   p >   : next move ")
         echo("|   p <   : previous move ")
         echo("|   p <<  : first position ")
         echo("| ")
         echo("| go: search methods for best move and PV generation ")
         echo("|   go    : method 1 > MTD-bi ")
         echo("|   go f  : method 2 > forced variation ")
         echo("|   go ab : method 3 > alpha-beta search ")
         echo("| ")
         echo("| book: init opening book ")
         echo("|_________________________________________________________________ ")
         echo("")
      elif comm.startsWith "test0":
         # Most critical for speed is move generation, so we perform a test.
         # If no second argument, the moveTable is not disabled
         # If second argument, the maxtimes is set to the second argument.
         # Note that the speed depends on the position (number of legal moves)
         var maxtimes = 10000   # default
         var mt_disabled: bool
         if comm.split.len == 1: mt_disabled = false else: mt_disabled = true
         if comm.split.len == 2: maxtimes = parseInt(comm.split[1])

         let t0 = cpuTime()

         block test0:
            var legalMoves: seq[Move]
            for i in 1..maxtimes:
               legalMoves = genMoves(pos.board)
               if mt_disabled: clearMoveTable()
         let t1 = cpuTime()
         echo "Time elapsed for move generation: ", $(t1 - t0), "  Max times: ", $maxtimes

      elif comm == "test1":
         # Display moveTable size
         echo "moveTable entries: ", $moveTableSize()

      elif comm == "test2":
         # Test
         discard


      else:  # ===================================
         echo("   Error (unkown command): ", comm)

# end main

when isMainModule:
   main()

#######################################################################

