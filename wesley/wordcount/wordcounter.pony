use ".."
use "collections"

class WordCounter is CanonicalForm
  let counts: Map[String, U64] = Map[String,U64]()
  let _punctuation: String = """ !"#$%&'()*+,-./:;<=>?@[\]^_`{|}~"""

  new create() =>
    this

  new create_from_map(map': Map[String, U64]) =>
    load_from_map(map')

  fun compare(that: CanonicalForm): MatchStatus val =>
    match that
    | let wc: WordCounter =>
      if counts.size() != wc.counts.size() then return ResultsDoNotMatch end
      for (key, count) in counts.pairs() do
        try
          if count != wc(key) then
  					return ResultsDoNotMatch
  				end
        else
          return ResultsDoNotMatch
        end
      end
      ResultsMatch
    else
      ResultsDoNotMatch
    end

  fun ref load_from_map(map': Map[String, U64]) =>
    for (key, count) in map'.pairs() do
      counts(key) = count
    end

  fun ref clear() =>
    counts.clear()

  fun clean(s: String): String =>
    """Strip characters based on a rule."""
    let charset = _punctuation
    recover val s.clone().lower().lstrip(charset).rstrip(charset) end

  fun ref update_from_string(s: String) =>
    for line in s.split("\n").values() do
      for word in line.split(" ").values() do
        _increment_word(word)
      end
    end

  fun ref _increment_word(word': String) =>
    let word = clean(word')
    if word == "" then return end
    try
      counts(word) = counts(word) + 1
    else
      counts(word) = 1
    end
 
  fun ref update_from_array(values: Array[(String, U64)]) =>
    for (word, count) in values.values() do
      update(word, count)
    end

  fun ref update(key': String, value: U64) =>
    let key = clean(key')
    if key == "" then return end
    counts(key) = value

  fun apply(key: String): U64 ? =>
    counts(key)

  fun string(): String =>
    """Return the string representation of the map"""
    var pairs = Array[String]()
    for (word, count) in counts.pairs() do
      pairs.append([word + ": " + count.string()])
    end
    "{ " + ", ".join(pairs) + " }"
