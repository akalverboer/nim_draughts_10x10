#=====================================================================
# Common data and tasks for MAD100.nim
#=====================================================================

from strutils import isLower, toLower, isUpper, toUpper

#======================================================================
# GLOBAL CONSTANTS
#======================================================================

## The MAX_NODES constant controls how much time we spend on looking for
## optimal moves. This is the default max number of nodes searched.
const MAX_NODES* = 2000

const WHITE* = 0
const BLACK* = 1

#======================================================================
# Type definition: Move
#======================================================================

type Move* = ref object of RootObj
   steps*: seq[int]
   takes*: seq[int]
   eval*: int

proc null*(Move: typedesc): Move =
   return Move(steps: @[], takes: @[], eval: 0)

proc isNull*(move: Move): bool =
   ## Test if variable of type Move has its default initial value
   if (move.steps == @[] and move.takes == @[]):
      return true
   else:
      return false

#======================================================================
# CLOSURE ITERATOR FOR SEQUENCE
#======================================================================
proc each*[T](sq: seq[T]): auto =
   ## Returns a closure iterator over a sequence
   ## Example:
   ##    var iterStr = @["aa","bb","cc","dd","ee"].each
   ##    for i in iterStr():
   ##       echo $i
   ##
   return iterator: T =
      for val in sq:
         yield val

#======================================================================
# EMPTY ITERATOR
#======================================================================
proc emptyIter*[T](): iterator(): T =
   ## Returns empty iterator of given type (required as parameter)
   ## Example:
   ##    block:
   ##       var it = emptyIter[int]()
   ##       for i in it():
   ##          echo $i     # does nothing
   ##       echo "Empty finished?: " & $it.finished   # echo 'true'
   ##
   result = iterator(): T {.closure.} =
      discard

#======================================================================
# ITERATOR TO SEQUENCE
#======================================================================
proc toSeq*[T](iter: iterator(): T, limit:int = -1): seq[T] =
   ##   toSeq(1;2;3) -> @[1,2,3]
   result = newSeq[T]()
   var x = iter()
   var i = 0
   while not finished(iter) and (limit == -1 or i < limit):
      result.add(x)
      x = iter()
      i += 1
   return result

#======================================================================
# REVERSE STRING/ARRAY
#======================================================================
proc reversed*(s: string): string =
   ## Returns a new string with chars in reversed order.
   result = newString(s.len)
   for i,c in s:
      result[s.high - i] = c

proc reversed*[T](a: openArray[T], first, last: int): seq[T] =
   ## Returns a new sequence with the items in reversed order.
   result = newSeq[T](last - first + 1)
   var x = first
   var y = last
   while x <= last:
      result[x] = a[y]
      dec(y)
      inc(x)

proc reversed*[T](a: openArray[T]): seq[T] =
   ## Returns a new openArray with the items in reversed order.
   reversed(a, 0, a.high)

#======================================================================
# STRING/CHAR MANIPULATION
#======================================================================

proc swapcase*(c: char): char =   # swapcase for characters
  ## Swap case for characters
  if c.isUpper:
    result = c.toLower
  else:
    result = c.toUpper

proc swapcase*(s: string): string =
   ## Swap case for strings
   ## Return a new string with each char in s swapped.
   ## Example:
   ##    let s = "aaaDDD888...+++XXX   yyy"
   ##    let t = s.swapcase
   ##
   result = newString(len(s))
   for i in 0..s.high:
      if s[i].isUpper:
         result[i] = s[i].toLower
      else:
         result[i] = s[i].toUpper
   return result

proc swapcase*[T](s: seq[T]): seq[T] =
   ## Swap case for sequence s of char/string
   ## Return a new sequence with each char in s swapped.
   ## Example:
   ##    let s = @['a', 'B', '0', '.', ' ', 'z', 'Z']
   ##    let t = s.swapcase
   ##
   ## if T != typedesc[string] and T != typedesc[char]: return s
   result = newSeq[T](len(s))
   for i in 0..s.high:
      result[i] = s[i].swapcase
   return result

proc toSeq*(s: string): seq[char] =
   ## Convert string to sequence of char
   ## Example:
   ##   let s = "Hello World"
   ##   let t = s.toSeq    # --> @['H', 'e', 'l', 'l', 'o', ' ', 'W', 'o', 'r', 'l', 'd' ]
   ##
   ##if T != typedesc[string] and T != typedesc[char]: return s
   result = newSeq[char](len(s))
   for i, c in s:
      result[i] = c
   return result

proc seqToStr*(s: seq[char]): string =
   ## Convert sequence of char to string
   ## Example:
   ##    let s = @['H', 'e', 'l', 'l', 'o', ' ', 'W', 'o', 'r', 'l', 'd' ]
   ##    let t = s.seqToStr    # --> "Hello World"
   ##
   result = newString(len(s))
   for i, c in s:
      result[i] = c
   return result

#======================================================================
# JUSTIFY with FIXED STRING LENGTH
proc justify(str: string, size: int, padStr: string = " ", right: bool = true): string =
   ##  If size is greater than the length of str, returns a new String of length size
   ##  with str left or right justified and padded with padStr; otherwise, returns str.
   ##  If right is true, the string is justified right else left.
   ##
   if padStr.len == 0: return str
   if size <= str.len: return str
   var padded: string = ""
   while padded.len < str.len + size:
      padded = padded & padStr
   var res = padded[0..(size - str.len - 1)]
   if right == true:
      return res & $str
   else:
      return $str & res

proc rjust*(str: string, size: int, padStr: string = " "): string =
   ##  Returns string of length size, right justified by padString
   ##  Example:
   ##     echo 7.intToStr.rjust(3,"0")   >>   output: 007
   ##
   justify(str, size, padStr, right = true)

proc ljust*(str: string, size: int, padStr: string = " "): string =
   ##  Returns string of length size, right justified by padString
   ##  Example:
   ##     echo "ABC".ljust(13,"231")   >>   output: ABC2312312312
   ##
   justify(str, size, padStr, right = false)

#======================================================================
# CREATE STRING FROM OTHER STRING
#======================================================================

proc map*(s: string, op: proc (c: char): char): string =
   ## Returns a new string with the results of op applied to every char.
   ## Example:
   ##   let s = "abcdefg"
   ##   let t = s.map(proc(c: char): char = c.toUpper )
   ##
   result = newString(s.len)
   for i in 0..s.high: result[i] = op(s[i])
   return result

template mapIt*(s: string, op: expr): string =
   ## Convenience template around the map proc to reduce typing.
   ## Example:
   ##   let s = "abcdefg"
   ##   let t = s.mapIt(it.toUpper)
   ##
   var res = newString(s.len)
   for i, it {.inject.} in s: res[i] = op
   res

#======================================================================
when isMainModule:
   # Test
   echo()
   echo "<<< Only for test; try mad100_run.nim >>> "
   echo()

#######################################################################
