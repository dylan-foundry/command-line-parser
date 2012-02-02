module: command-line-parser
synopsis: Parse command-line options.
authors: Eric Kidd
copyright: Copyright 1998 Eric Kidd

//======================================================================
//
//  Copyright (c) 1998 Eric Kidd
//  All rights reserved.
//
//  Use and copying of this software and preparation of derivative
//  works based on this software are permitted, including commercial
//  use, provided that the following conditions are observed:
//
//  1. This copyright notice must be retained in full on any copies
//     and on appropriate parts of any derivative works. (Other names
//     and years may be added, so long as no existing ones are removed.)
//
//  This software is made available "as is".  Neither the authors nor
//  Carnegie Mellon University make any warranty about the software,
//  its performance, or its conformity to any specification.
//
//  Bug reports, questions, comments, and suggestions should be sent by
//  E-mail to the Internet address "gd-bugs@gwydiondylan.org".
//
//======================================================================

//======================================================================
//  The All-Singing, All-Dancing Argument Parser
//======================================================================
//  Ole J. Tetlie wrote an option parser, and it was pretty good. But it
//  didn't support all the option types required by d2c, and besides, we
//  felt a need to overdo something.
//
//  So this code is redesigned and rewritten from the ground up. Our design
//  goals were to support all common types of options and allow the user of
//  the library to add support for the less common ones.
//
//  To parse a list of arguments, you need to perform the following steps:
//
//    1. Create an <argument-list-parser>.
//    2. Create individual <option-parser>s and attach them to it.
//    3. Tell the <argument-list-parser> to parse a list of strings.
//    4. Call option-value or option-value-long-name to retrieve your
//       option data.
//    5. Reuse your option parser by calling parse-arguments again, or
//       just forget about it.
//
//  A note about terminology:
//    foo -x --y=bar baz
//
//  All the tokens on that command line are arguments. "-x" and "--y"
//  are options, and "bar" is a parameter. "baz" is a regular argument.


// todo -- There is no error signalled if two options have the same short name
//         (or long name, I assume).  In fact there's a comment saying that the
//         rightmost argument with the same name takes precedence.  So this is
//         by design???
//
// todo -- There is no indication of default values in the generated synopsis,
//         and the syntax for specifying "syntax" and docstring is bizarre at
//         best.  --cgay 2006.11.27


//======================================================================
//  <argument-list-parser>
//======================================================================

define open class <argument-list-parser> (<object>)
  // Retained across calls to parse-arguments.
  slot option-parsers :: <stretchy-vector> /* of <option-parser> */ =
    make(<stretchy-vector> /* of <option-parser> */);
  constant slot option-short-name-map :: <string-table> /* of <option-parser> */ =
    make(<string-table>);
  constant slot option-long-name-map :: <string-table> /* of <option-parser> */ =
    make(<string-table>);
  constant slot parameter-options :: <string-table> /* of <boolean> */ =
    make(<string-table>);

  // Information generated by parsing arguments.
  constant slot tokens :: <deque> /* of: <argument-token> */ =
    make(<deque> /* of: <argument-token> */);
  slot regular-arguments :: <stretchy-vector> /* of: <string> */ =
    make(<stretchy-vector> /* of: <string> */);
end class <argument-list-parser>;

define function add-option-parser
    (args-parser :: <argument-list-parser>, opt-parser :: <option-parser>)
 => ()
  local method add-to-table(table, items, value) => ()
          for (item in items)
            table[item] := value;
          end for;
        end method add-to-table;
  args-parser.option-parsers := add!(args-parser.option-parsers, opt-parser);
  add-to-table(args-parser.option-long-name-map,
               opt-parser.long-option-names,
               opt-parser);
  add-to-table(args-parser.option-short-name-map,
               opt-parser.short-option-names,
               opt-parser);
  if (opt-parser.option-might-have-parameters?)
    add-to-table(args-parser.parameter-options,
                 opt-parser.short-option-names,
                 #t);
  end if;
end function add-option-parser;

define function option-parser-by-long-name
    (parser :: <argument-list-parser>, long-name :: <string>)
 => (value :: <option-parser>)
  parser.option-long-name-map[long-name];
end;

define function option-present?-by-long-name
    (parser :: <argument-list-parser>, long-name :: <string>)
 => (value :: <boolean>)
  option-parser-by-long-name(parser, long-name).option-present?;
end;

define function option-value-by-long-name
    (parser :: <argument-list-parser>, long-name :: <string>)
 => (value :: <object>)
  option-parser-by-long-name(parser, long-name).option-value;
end;

define function add-argument-token
    (parser :: <argument-list-parser>,
     class :: <class>,
     value :: <string>,
     #rest keys, #key, #all-keys)
 => ()
  push-last(parser.tokens, apply(make, class, value: value, keys));
end;

define function argument-tokens-remaining?
    (parser :: <argument-list-parser>)
 => (remaining? :: <boolean>)
  ~parser.tokens.empty?
end;

define function peek-argument-token
    (parser :: <argument-list-parser>)
 => (token :: false-or(<argument-token>))
  unless (argument-tokens-remaining?(parser))
    usage-error()
  end;
  parser.tokens[0];
end;

define function get-argument-token
    (parser :: <argument-list-parser>)
 => (token :: false-or(<argument-token>))
  unless (argument-tokens-remaining?(parser))
    usage-error()
  end;
  pop(parser.tokens);
end;


//======================================================================
//  <option-parser>
//======================================================================

define abstract open primary class <option-parser> (<object>)
  // Information used by <option-list-parser>
  slot long-option-names :: <list>,
    init-keyword: long-options:,
    init-value: #();
  slot short-option-names :: <list>,
    init-keyword: short-options:,
    init-value: #();
  slot option-might-have-parameters? :: <boolean> = #t;
  slot option-description :: <string>,
    init-keyword: description:,
    init-value: "";
  // Information generated by parsing arguments.
  slot option-present? :: <boolean>,
    init-value: #f;
  slot option-value :: <object>,
    init-value: #f;
end class <option-parser>;

define open generic reset-option-parser(parser :: <option-parser>) => ();

define method reset-option-parser(parser :: <option-parser>) => ()
  parser.option-present? := #f;
  parser.option-value := #f;
end method reset-option-parser;

define open generic parse-option
    (opt :: <option-parser>, args :: <argument-list-parser>) => ();

define function add-option-parser-by-type
    (parser :: <argument-list-parser>,
     class :: <class>,
     #rest keys)
 => ()
  add-option-parser(parser, apply(make, class, keys));
end function add-option-parser-by-type;


//======================================================================
//  <argument-token> (and subclasses)
//======================================================================

define abstract class <argument-token> (<object>)
  constant slot token-value :: <string>,
    required-init-keyword: value:;
end class <argument-token>;

define class <regular-argument-token> (<argument-token>)
end class <regular-argument-token>;

define abstract class <option-token> (<argument-token>)
end class <option-token>;

define class <short-option-token> (<option-token>)
  constant slot tightly-bound-to-next-token?,
    init-keyword: tightly-bound?:,
    init-value: #f;
end class <short-option-token>;

define class <long-option-token> (<option-token>)
end class <long-option-token>;

define class <equals-token> (<argument-token>)
end class <equals-token>;


//======================================================================
//  usage-error
//======================================================================

define class <usage-error> (<error>)
end class <usage-error>;

define function usage-error () => ()
  error(make(<usage-error>));
end;


//======================================================================
//  parse-arguments
//======================================================================

// Break up our arguments around '--' in the traditional fashion.
define function split-args(argv)
 => (clean-args :: <sequence>, extra-args :: <sequence>)
  let splitter = find-key(argv, curry(\=, "--"));
  if (splitter)
    let clean-args = copy-sequence(argv, end: splitter);
    let extra-args = copy-sequence(argv, start: splitter + 1);
    values (clean-args, extra-args);
  else
    values(argv, #());
  end if;
end function split-args;

// Chop things up around '=' characters.
define function chop-args(clean-args)
 => (chopped :: <deque> /* of: <string> */)
  let chopped = make(<deque> /* of: <string> */);
  local method store(str)
          push-last(chopped, str);
        end method store;
  for (arg in clean-args)
    case
      (arg.size = 0) =>
        store("");
      (arg[0] = '=') =>
        store("=");
        if (arg.size > 1)
          store(copy-sequence(arg, start: 1));
        end if;
      (arg[0] = '-') =>
        let break = subsequence-position(arg, "=");
        if (break)
          store(copy-sequence(arg, end: break));
          store("=");
          if (arg.size > break + 1)
            store(copy-sequence(arg, start: break + 1));
          end if;
        else
          store(arg);
        end if;
      otherwise =>
        store(arg);
    end case;
  end for;
  chopped;
end function chop-args;

// Turn a deque of args into an internal deque of tokens.
define function tokenize-args
    (parser :: <argument-list-parser>,
     args :: <deque> /* of: <string> */)
 => ()
  until (args.empty?)
    let arg = pop(args);
    local

      // Attempt to get the next argument a little bit early.
      method next-arg() => (arg :: <string>)
        if (~args.empty?)
          pop(args);
        else
          usage-error();
          ""                                           // stifle warning
        end;
      end method,

      // Add a token to our deque
      method token(class :: <class>, value :: <string>,
                   #rest keys, #key, #all-keys) => ()
        apply(add-argument-token, parser, class, value, keys);
      end method;

    // Process an individual argument
    case
      (arg = "=") =>
        token(<equals-token>, "=");
        token(<regular-argument-token>, next-arg());

      (arg.size > 2 & arg[0] = '-' & arg[1] = '-') =>
        token(<long-option-token>, copy-sequence(arg, start: 2));

      (arg.size > 0 & arg[0] = '-') =>
        if (arg.size = 1)
          // Probably a fake filename representing stdin ('cat -')
          token(<regular-argument-token>, "-");
        else
          block (done)
            for (i from 1 below arg.size)
              let opt = make(<string>, size: 1, fill: arg[i]);
              let opt-parser = element(parser.option-short-name-map,
                                       opt, default: #f);
              if (opt-parser & opt-parser.option-might-have-parameters?
                    & i + 1 < arg.size)
                // Take rest of argument, and use it as a parameter.
                token(<short-option-token>, opt, tightly-bound?: #t);
                token(<regular-argument-token>,
                      copy-sequence(arg, start: i + 1));
                done();
              else
                // A regular, solitary option with no parameter.
                token(<short-option-token>, opt);
              end if;
            end for;
          end block;
        end if;

      otherwise =>
        token(<regular-argument-token>, arg);
    end case;
  end until;
end function tokenize-args;

define function get-option-parser
    (parsers :: <string-table>, key :: <string>)
 => (parser :: <option-parser>)
  let parser = element(parsers, key, default: #f);
  unless (parser)
    usage-error();
  end;
  parser;
end;

define function parse-arguments
    (parser :: <argument-list-parser>, argv :: <sequence>)
 => (success? :: <boolean>)
  block ()
    parser.tokens.size := 0;
    parser.regular-arguments.size := 0;
    do(reset-option-parser, parser.option-parsers);

    // Split our args around '--' and chop them around '='.
    let (clean-args, extra-args) = split-args(argv);
    let chopped-args = chop-args(clean-args);

    // Tokenize our arguments and suck them into the parser.
    tokenize-args(parser, chopped-args);

    // Process our tokens.
    while (argument-tokens-remaining?(parser))
      let token = peek-argument-token(parser);
      select (token by instance?)
        <regular-argument-token> =>
          get-argument-token(parser);
          parser.regular-arguments := add!(parser.regular-arguments,
                                           token.token-value);
        <short-option-token> =>
          let opt-parser =
            get-option-parser(parser.option-short-name-map, token.token-value);
          parse-option(opt-parser, parser);
          opt-parser.option-present? := #t;
        <long-option-token> =>
          let opt-parser =
            get-option-parser(parser.option-long-name-map, token.token-value);
          parse-option(opt-parser, parser);
          opt-parser.option-present? := #t;
        otherwise =>
          usage-error();
      end select;
    end while;

    // And append any more regular arguments from after the '--'.
    for (arg in extra-args)
      parser.regular-arguments := add!(parser.regular-arguments, arg);
    end for;

    #t;
  exception (<usage-error>)
    #f;
  end block;
end function parse-arguments;

define open generic print-synopsis
 (parser :: <argument-list-parser>, stream :: <stream>, #key);

// todo -- Generate the initial "Usage: ..." line as well.
define method print-synopsis
    (parser :: <argument-list-parser>,
     stream :: <stream>,
     #key usage :: false-or(<string>),
          description :: false-or(<string>))
  if (usage) format(stream, "Usage: %s\n", usage); end;
  if (description) format(stream, "%s\n", description); end;
  if (usage | description) new-line(stream); end;
  local method print-option (short, long, description);
          let short = select (short by instance?)
                        <list> => ~empty?(short) & first(short);
                        <string> => short;
                        otherwise => #f;
                      end select;
          let long = select (long by instance?)
                       <pair> => ~empty?(long) & first(long);
                       <string> => long;
                       otherwise => #f;
                     end select;
          write(stream, "  ");
          if (short)
            format(stream, "-%s", short);
            write(stream, if (long) ", " else "  " end);
          else
            write(stream, "    ");
          end if;
          if (long)
            format(stream, "--%s", long);
            for (i from 1 to 28 - 2 - size(long))
              write-element(stream, ' ');
            end for;
          else
            format(stream, "%28s", "");
          end if;
          write(stream, description);
          new-line(stream);
        end method print-option;

  for (option in option-parsers(parser))
    print-option(short-option-names(option),
                 long-option-names(option),
                 option-description(option));
  end;
end method print-synopsis;

/*
  Semi-comprehensible design notes, here for historical interest:

  add-option-templates
  parse-options
  find-option-value
  print-synopsis
  hypothetical: execute-program?

  don't forget --help and --version, which exit immediately
  program names...
  erroneous argument lists

  Parameterless options:
   -b, --bar, --no-bar
     Present or absent. May have opposites; latter values override
     previous values.

  Parameter options:
   -f x, --foo=x
     May be specified multiple times; this indicates multiple values.

  Immediate-exit options:
   --help, --version

  Key/value options:
   -DFOO -DBAR=1

  Degenerate options forms we don't approve of:
   -vvvvv (multiple verbosity)
   -z3 (optional parameter)

  Tokenization:
   b -> -b
   f x -> -f x
   fx -> -f x
   foo=x -> -foo =x
   DFOO -> -D FOO
   DBAR=1 -> -D BAR =1
   bfx -> b f x
   fbx -> f bx

  Four kinds of tokens:
   Options
   Values
   Explicit parameter values
   Magic separator '--' (last token; no more!)

  <option-descriptor> protocol:
    define method on process-option
    call get-parameter and get-optional-parameter as needed
*/
