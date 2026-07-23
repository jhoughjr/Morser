//
//  CommonWords.swift
//  MorserX
//
//  Word lists for copy practice. Embedded as Swift rather than bundled as a
//  text file because the project uses filesystem-synchronised groups, which
//  pick up .swift automatically but would need a Copy Bundle Resources phase
//  for a resource.
//

enum CommonWords {

    /// Short, high-frequency English words — the ones worth hearing as a single
    /// shape rather than spelling out letter by letter.
    static let english: [String] = [
        "a", "able", "about", "above", "act", "add", "after", "age", "ago", "aid", "aim", "air", "all", "also", "am", "an", "and", "any", "are", "as", "ask", "at", "away", "back", "bad", "bag", "be", "bear", "been", "before", "being", "best", "better", "big", "bird", "black", "blue", "boat", "body", "book", "both", "boy", "bring", "brown", "build", "built", "but", "by", "call", "came", "can", "car", "care", "case", "change", "check", "child", "city", "class", "clean", "clear", "close", "cold", "come", "could", "cut", "dark", "day", "dead", "deal", "deep", "did", "die", "do", "does", "done", "door", "down", "draw", "dream", "drew", "dress", "drink", "drive", "drop", "due", "each", "early", "easy", "eat", "eight", "end", "even", "ever", "every", "eye", "face", "fact", "fail", "fall", "far", "fear", "feel", "few", "field", "fill", "find", "fine", "fire", "first", "fish", "five", "fix", "flat", "floor", "fly", "focus", "follow", "food", "foot", "for", "form", "found", "four", "free", "fresh", "from", "front", "full", "fun", "game", "gas", "gave", "get", "give", "glass", "go", "goal", "gold", "gone", "good", "got", "grass", "great", "green", "group", "grow", "hair", "half", "hand", "hang", "hard", "has", "hat", "have", "head", "hear", "heard", "heart", "heat", "help", "here", "high", "hill", "him", "himself", "his", "hit", "hold", "hole", "home", "hope", "horse", "hot", "hour", "house", "how", "hung", "hurt", "idea", "if", "in", "into", "is", "it", "its", "itself", "join", "jump", "just", "keep", "kept", "key", "kind", "king", "knew", "know", "lake", "land", "large", "last", "late", "law", "lay", "lead", "learn", "leave", "left", "let", "letter", "lie", "life", "light", "like", "line", "list", "live", "long", "look", "lose", "loss", "lost", "lot", "loud", "love", "low", "made", "main", "make", "man", "many", "mark", "may", "mean", "men", "mile", "mind", "miss", "model", "money", "month", "more", "most", "move", "much", "must", "my", "myself", "name", "near", "need", "never", "new", "next", "nice", "night", "no", "nose", "not", "note", "now", "of", "off", "old", "on", "once", "one", "only", "open", "or", "other", "our", "out", "over", "own", "pain", "part", "pass", "past", "pay", "place", "plan", "play", "please", "point", "poor", "pull", "push", "put", "race", "radio", "raise", "read", "ready", "real", "red", "rest", "right", "road", "rock", "room", "round", "rule", "run", "said", "sale", "same", "save", "say", "sea", "seat", "see", "seem", "seen", "self", "send", "sent", "set", "shall", "shape", "share", "she", "sheet", "ship", "short", "shot", "should", "show", "shown", "shut", "sick", "side", "sight", "sign", "simple", "sing", "site", "six", "size", "small", "so", "soft", "some", "son", "song", "soon", "sound", "south", "space", "speak", "spend", "spoke", "sport", "spring", "staff", "stand", "start", "stay", "step", "still", "stop", "store", "story", "street", "such", "suit", "sun", "sure", "swim", "take", "talk", "teach", "team", "tell", "ten", "test", "text", "than", "thank", "that", "the", "their", "them", "then", "there", "these", "they", "thing", "think", "this", "those", "three", "time", "to", "today", "told", "told", "tone", "took", "tool", "top", "town", "track", "trade", "tree", "tried", "trip", "true", "try", "turn", "two", "under", "up", "us", "use", "very", "view", "visit", "voice", "vote", "wait", "walk", "wall", "want", "warm", "water", "wave", "way", "wear", "week", "well", "went", "were", "west", "what", "when", "where", "which", "while", "white", "who", "whole", "why", "wide", "wife", "wild", "will", "wish", "with", "woman", "word", "work", "world", "would", "write", "wrong", "year", "yes", "you", "young", "your", "zone"
    ]

    /// The on-air vocabulary. Small and endlessly repeated, which is exactly why
    /// it is learnable in whole chunks.
    static let radio: [String] = [
        "cq", "de", "qrz", "qsx", "qsy", "qth", "qtr", "qro", "qrp", "qrt", "qry", "qsa", "qsb", "qsd", "qsk", "qsl", "qsm", "qso", "qsp", "qss", "qst", "qt", "qtc", "qua", "qzc",
        "rst", "tnx", "pse", "agn", "cfm", "hpe", "cuagn", "es", "gm", "ga", "ge", "om", "yl", "dx", "hr", "ur", "wx", "ant", "rig", "pwr",
        "73", "88", "599"
    ]
}
