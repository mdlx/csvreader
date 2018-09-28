# encoding: utf-8

class CsvReader





class Parser


## char constants
DOUBLE_QUOTE = "\""
BACKSLASH    = "\\"    ## use BACKSLASH_ESCAPE ??
COMMENT      = "#"      ## use COMMENT_HASH or HASH or ??
SPACE        = " "      ##   \s == ASCII 32 (dec)            =    (Space)
TAB          = "\t"     ##   \t == ASCII 0x09 (hex)          = HT (Tab/horizontal tab)
LF	         = "\n"     ##   \n == ASCII 0x0A (hex) 10 (dec) = LF (Newline/line feed)
CR	         = "\r"     ##   \r == ASCII 0x0D (hex) 13 (dec) = CR (Carriage return)


###################################
## add simple logger with debug flag/switch
#
#  use Parser.debug = true   # to turn on
#
#  todo/fix: use logutils instead of std logger - why? why not?

def self.logger() @@logger ||= Logger.new( STDOUT ); end
def logger()  self.class.logger; end



attr_reader :config   ## todo/fix: change config to proper dialect class/struct - why? why not?

def initialize( sep:         ',',
                quote:       DOUBLE_QUOTE, ## note: set to nil for no quote
                doublequote: true,
                trim:        true,   ## note: will toggle between human/default and strict mode parser!!!
                na:          ['\N', 'NA'],  ## note: set to nil for no null vales / not availabe (na)
                quoted_empty:   '',   ## note: only available in strict mode (e.g. trim=false)
                unquoted_empty: '' ,   ## note: only available in strict mode (e.g. trim=false)
                comment:     nil,    ## note: only available in strict mode (always on in default/human/std mode)
                escape:      nil    ## note: only available in strict mode (alway on in default/human/std mode); set to nil for no escapes
               )
  @config = {}   ## todo/fix: change config to proper dialect class/struct - why? why not?
  @config[:sep]          = sep
  @config[:quote]        = quote
  @config[:doublequote]  = doublequote
  @config[:escape]  = escape
  @config[:trim]         = trim
  @config[:na]     = na
  @config[:quoted_empty] = quoted_empty
  @config[:unquoted_empty] = unquoted_empty
  @config[:comment] = comment
end



def strict?
  ## note:  use trim for separating two different parsers / code paths:
  ##   - human with trim leading and trailing whitespace and
  ##   - strict with no leading and trailing whitespaces allowed

  ## for now use - trim == false for strict version flag alias
  ##   todo/fix: add strict flag - why? why not?
  @config[:trim] ? false : true
end


DEFAULT = new( sep: ',', trim: true )
RFC4180 = new( sep: ',', trim: false )
EXCEL   = new( sep: ',', trim: false )

def self.default()  DEFAULT; end    ## alternative alias for DEFAULT
def self.rfc4180()  RFC4180; end    ## alternative alias for RFC4180
def self.excel()    EXCEL; end      ## alternative alias for EXCEL




def parse_escape( io )
  value = ""
  if io.peek == BACKSLASH
    io.getc ## eat-up backslash
    if (c=io.peek; c==BACKSLASH || c==LF || c==CR || c==',' || c=='"' )
      value << io.getc     ## add escaped char (e.g. lf, cr, etc.)
    else
      ## unknown escape sequence; no special handling/escaping
      value << BACKSLASH
    end
  else
    puts "*** csv parse error: found >#{io.peek} (#{io.peek.ord})< - BACKSLASH (\\) expected in parse_escape!!!!"
    exit(1)
  end
  value
end


def parse_doublequote( io )
  value = ""
  if io.peek == DOUBLE_QUOTE
    io.getc  ## eat-up double_quote

    loop do
      while (c=io.peek; !(c==DOUBLE_QUOTE || c==BACKSLASH || io.eof?))
        value << io.getc   ## eat-up everything until hitting double_quote (") or backslash (escape)
      end

      if io.eof?
        break
      elsif io.peek == BACKSLASH
        value << parse_escape( io )
      else   ## assume io.peek == DOUBLE_QUOTE
        io.getc ## eat-up double_quote
        if io.peek == DOUBLE_QUOTE  ## doubled up quote?
          value << io.getc   ## add doube quote and continue!!!!
        else
          break
        end
      end
    end
  else
    puts "*** csv parse error: found >#{io.peek} (#{io.peek.ord})< - DOUBLE_QUOTE (\") expected in parse_double_quote!!!!"
    exit(1)
  end
  value
end



def parse_field( io, sep: )
  logger.debug "parse field - sep: >#{sep}< (#{sep.ord})"  if logger.debug?

  value = ""
  skip_spaces( io )   ## strip leading spaces

  if (c=io.peek; c=="," || c==LF || c==CR || io.eof?) ## empty field
     ## return value; do nothing
  elsif io.peek == DOUBLE_QUOTE
    logger.debug "start double_quote field - peek >#{io.peek}< (#{io.peek.ord})"  if logger.debug?
    value << parse_doublequote( io )

    ## note: always eat-up all trailing spaces (" ") and tabs (\t)
    skip_spaces( io )
    logger.debug "end double_quote field - peek >#{io.peek}< (#{io.peek.ord})"  if logger.debug?
  else
    logger.debug "start reg field - peek >#{io.peek}< (#{io.peek.ord})"  if logger.debug?
    ## consume simple value
    ##   until we hit "," or "\n" or "\r"
    ##    note: will eat-up quotes too!!!
    while (c=io.peek; !(c=="," || c==LF || c==CR || io.eof?))
      if io.peek == BACKSLASH
        value << parse_escape( io )
      else
        logger.debug "  add char >#{io.peek}< (#{io.peek.ord})"  if logger.debug?
        value << io.getc   ## note: eat-up all spaces (" ") and tabs (\t) too (strip trailing spaces at the end)
      end
    end
    value = value.strip   ## strip all trailing spaces
    logger.debug "end reg field - peek >#{io.peek}< (#{io.peek.ord})"  if logger.debug?
  end

  value
end




def parse_field_strict( io, sep: )
  logger.debug "parse field (strict) - sep: >#{sep}< (#{sep.ord})"  if logger.debug?

  value = ""

  if (c=io.peek; c==sep || c==LF || c==CR || io.eof?) ## empty unquoted field
     value = config[:unquoted_empty]   ## defaults to "" (might be set to nil if needed)
     ## return value; do nothing
  elsif config[:quote] && io.peek == config[:quote]
    logger.debug "start quote field (strict) - peek >#{io.peek}< (#{io.peek.ord})"  if logger.debug?
    io.getc  ## eat-up double_quote

    loop do
      while (c=io.peek; !(c==config[:quote] || io.eof?))
        value << io.getc   ## eat-up everything unit quote (")
      end

      break if io.eof?

      io.getc ## eat-up double_quote

      if config[:doublequote] && io.peek == config[:quote]  ## doubled up quote?
        value << io.getc   ## add doube quote and continue!!!!
      else
        break
      end
    end

    value = config[:quoted_empty]  if value == ""   ## defaults to "" (might be set to nil if needed)

    logger.debug "end double_quote field (strict) - peek >#{io.peek}< (#{io.peek.ord})"  if logger.debug?
  else
    logger.debug "start reg field (strict) - peek >#{io.peek}< (#{io.peek.ord})"  if logger.debug?
    ## consume simple value
    ##   until we hit "," or "\n" or "\r" or stroy "\"" double quote
    while (c=io.peek; !(c==sep || c==LF || c==CR || c==config[:quote] || io.eof?))
      logger.debug "  add char >#{io.peek}< (#{io.peek.ord})"  if logger.debug?
      value << io.getc
    end
    logger.debug "end reg field (strict) - peek >#{io.peek}< (#{io.peek.ord})"  if logger.debug?
  end

  value
end



def parse_record( io, sep: )
  values = []

  loop do
     value = parse_field( io, sep: sep )
     logger.debug "value: »#{value}«"  if logger.debug?
     values << value

     if io.eof?
        break
     elsif (c=io.peek; c==LF || c==CR)
       skip_newlines( io )
       break
     elsif io.peek == ","
       io.getc   ## eat-up FS(,)
     else
       puts "*** csv parse error: found >#{io.peek} (#{io.peek.ord})< - FS (,) or RS (\\n) expected!!!!"
       exit(1)
     end
  end

  values
end



def parse_record_strict( io, sep: )
  values = []

  loop do
     value = parse_field_strict( io, sep: sep )
     logger.debug "value: »#{value}«"  if logger.debug?
     values << value

     if io.eof?
        break
     elsif (c=io.peek; c==LF || c==CR)
       skip_newline( io )   ## note: singular / single newline only (NOT plural)
       break
     elsif io.peek == sep
       io.getc   ## eat-up FS (,)
     else
       puts "*** csv parse error (strict): found >#{io.peek} (#{io.peek.ord})< - FS (,) or RS (\\n) expected!!!!"
       exit(1)
     end
  end

  values
end



def skip_newlines( io )
  return if io.eof?

  while (c=io.peek; c==LF || c==CR)
    io.getc    ## eat-up all \n and \r
  end
end


def skip_newline( io )    ## note: singular (strict) version
  return if io.eof?

  ## only skip CR LF or LF or CR
  if io.peek == CR
    io.getc ## eat-up
    io.getc  if io.peek == LF
  elsif io.peek == LF
    io.getc ## eat-up
  else
    # do nothing
  end
end



def skip_until_eol( io )
  return if io.eof?

  while (c=io.peek; !(c==LF || c==CR || io.eof?))
    io.getc    ## eat-up all until end of line
  end
end

def skip_spaces( io )
  return if io.eof?

  while (c=io.peek; c==SPACE || c==TAB)
    io.getc   ## note: always eat-up all spaces (" ") and tabs (\t)
  end
end






def parse_lines_human( io, sep:, &block )

  loop do
    break if io.eof?

    skip_spaces( io )

    if io.peek == COMMENT        ## comment line
      logger.debug "skipping comment - peek >#{io.peek}< (#{io.peek.ord})"  if logger.debug?
      skip_until_eol( io )
      skip_newlines( io )
    elsif (c=io.peek; c==LF || c==CR || io.eof?)
      logger.debug "skipping blank - peek >#{io.peek}< (#{io.peek.ord})"  if logger.debug?
      skip_newlines( io )
    else
      logger.debug "start record - peek >#{io.peek}< (#{io.peek.ord})"  if logger.debug?

      record = parse_record( io, sep: sep )
      ## note: requires block - enforce? how? why? why not?
      block.call( record )   ## yield( record )
    end
  end  # loop
end # method parse_lines_human



def parse_lines_strict( io, sep:, &block )

  ## no leading and trailing whitespaces trimmed/stripped
  ## no comments skipped
  ## no blanks skipped
  ## - follows strict rules of
  ##  note: this csv format is NOT recommended;
  ##    please, use a format with comments, leading and trailing whitespaces, etc.
  ##    only added for checking compatibility

  loop do
    break if io.eof?

    logger.debug "start record (strict) - peek >#{io.peek}< (#{io.peek.ord})"  if logger.debug?

    if config[:comment] && io.peek == config[:comment]        ## comment line
      logger.debug "skipping comment - peek >#{io.peek}< (#{io.peek.ord})"  if logger.debug?
      skip_until_eol( io )
      skip_newline( io )
    else
      record = parse_record_strict( io, sep: sep )
      ## note: requires block - enforce? how? why? why not?
      block.call( record )   ## yield( record )
    end
  end  # loop
end # method parse_lines_strict



def parse_lines( io_maybe, sep: config[:sep], &block )
  ## find a better name for io_maybe
  ##   make sure io is a wrapped into BufferIO!!!!!!
  if io_maybe.is_a?( BufferIO )    ### allow (re)use of BufferIO if managed from "outside"
    io = io_maybe
  else
    io = BufferIO.new( io_maybe )
  end

  if strict?
    parse_lines_strict( io, sep: sep, &block )
  else
    parse_lines_human( io, sep: sep, &block )
  end
end  ## parse_lines



##   fix: add optional block  - lets you use it like foreach!!!
##    make foreach an alias of parse with block - why? why not?
##
##   unifiy with (make one) parse and parse_lines!!!! - why? why not?

def parse( io_maybe, sep: config[:sep], limit: nil )
  records = []

  parse_lines( io_maybe, sep: sep  ) do |record|
    records << record

    ## set limit to 1 for processing "single" line (that is, get one record)
    break  if limit && limit >= records.size
  end

  records
end ## method parse



end # class Parser
end # class CsvReader
