import Foundation

/// Word lists for recovery phrase generation.
/// Designed to create memorable sentences with high entropy.
enum WordLists {

    // MARK: - Articles (small pool, low entropy contribution)

    static let articles: [String] = [
        "the", "a", "an", "that", "this", "one", "some", "each", "every"
    ]

    // MARK: - Possessives

    static let possessives: [String] = [
        "my", "your", "his", "her", "their", "our", "its"
    ]

    // MARK: - Numbers (for variety)

    static let numbers: [String] = [
        "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
        "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen",
        "twenty", "thirty", "forty", "fifty", "sixty", "hundred"
    ]

    // MARK: - Adjectives (large pool for entropy)

    static let adjectives: [String] = [
        "purple", "golden", "silver", "ancient", "modern", "broken", "shiny",
        "dusty", "foggy", "sunny", "rainy", "windy", "stormy", "calm",
        "quiet", "loud", "soft", "hard", "warm", "cold", "hot", "cool",
        "happy", "sad", "angry", "gentle", "rough", "smooth", "sharp",
        "dull", "bright", "dark", "light", "heavy", "tiny", "huge",
        "small", "large", "tall", "short", "wide", "narrow", "thick",
        "thin", "deep", "shallow", "high", "low", "fast", "slow",
        "quick", "lazy", "busy", "empty", "full", "open", "closed",
        "new", "old", "young", "fresh", "stale", "sweet", "sour",
        "bitter", "salty", "spicy", "bland", "rich", "poor", "fancy",
        "plain", "simple", "complex", "easy", "difficult", "strange",
        "normal", "unusual", "common", "rare", "famous", "unknown",
        "secret", "hidden", "visible", "invisible", "magic", "ordinary",
        "special", "unique", "boring", "exciting", "scary", "funny",
        "serious", "playful", "careful", "careless", "brave", "fearful",
        "strong", "weak", "healthy", "sick", "clean", "dirty", "neat",
        "messy", "tidy", "wild", "tame", "fierce", "peaceful", "noisy",
        "silent", "musical", "artistic", "creative", "logical", "random",
        "perfect", "flawed", "crooked", "straight", "curved", "twisted",
        "frozen", "melted", "burning", "glowing", "sparkling", "fading",
        "growing", "shrinking", "floating", "sinking", "flying", "crawling",
        "sleeping", "waking", "dreaming", "thinking", "wondering", "knowing",
        "forgotten", "remembered", "lost", "found", "missing", "present",
        "absent", "nearby", "distant", "foreign", "local", "northern",
        "southern", "eastern", "western", "central", "outer", "inner",
        "upper", "lower", "front", "back", "left", "right", "middle",
        "wooden", "metal", "glass", "paper", "plastic", "stone", "brick",
        "leather", "cotton", "silk", "velvet", "woolen", "fluffy", "prickly"
    ]

    // MARK: - Nouns (large pool for entropy)

    static let nouns: [String] = [
        "elephant", "tiger", "monkey", "dolphin", "penguin", "giraffe",
        "zebra", "kangaroo", "koala", "panda", "lion", "bear", "wolf",
        "fox", "rabbit", "squirrel", "mouse", "cat", "dog", "horse",
        "cow", "pig", "sheep", "goat", "chicken", "duck", "goose",
        "eagle", "owl", "parrot", "sparrow", "crow", "swan", "peacock",
        "butterfly", "dragonfly", "bee", "spider", "ant", "snail",
        "fish", "shark", "whale", "octopus", "crab", "lobster", "turtle",
        "snake", "lizard", "frog", "crocodile", "dinosaur", "dragon",
        "unicorn", "phoenix", "mermaid", "wizard", "witch", "knight",
        "princess", "prince", "king", "queen", "emperor", "warrior",
        "pirate", "sailor", "captain", "soldier", "doctor", "teacher",
        "artist", "musician", "dancer", "singer", "actor", "writer",
        "poet", "scientist", "engineer", "pilot", "astronaut", "chef",
        "baker", "farmer", "gardener", "carpenter", "blacksmith", "tailor",
        "mountain", "valley", "river", "lake", "ocean", "island", "beach",
        "forest", "jungle", "desert", "meadow", "garden", "park", "field",
        "castle", "palace", "tower", "bridge", "tunnel", "cave", "temple",
        "church", "mosque", "library", "museum", "theater", "stadium",
        "school", "hospital", "factory", "warehouse", "lighthouse", "windmill",
        "fountain", "statue", "monument", "pyramid", "ruin", "fortress",
        "village", "city", "town", "harbor", "airport", "station",
        "table", "chair", "bed", "sofa", "desk", "shelf", "cabinet",
        "mirror", "window", "door", "gate", "fence", "wall", "roof",
        "clock", "lamp", "candle", "lantern", "torch", "fire", "flame",
        "book", "letter", "map", "compass", "telescope", "microscope",
        "camera", "piano", "violin", "guitar", "drum", "trumpet", "flute",
        "sword", "shield", "bow", "arrow", "spear", "hammer", "axe",
        "key", "lock", "chain", "rope", "wheel", "gear", "spring",
        "crystal", "diamond", "ruby", "emerald", "pearl", "gold", "silver",
        "crown", "ring", "necklace", "bracelet", "pendant", "treasure",
        "umbrella", "hat", "scarf", "glove", "boot", "coat", "dress",
        "apple", "orange", "lemon", "cherry", "grape", "banana", "melon",
        "bread", "cake", "cookie", "candy", "chocolate", "honey", "butter",
        "coffee", "tea", "milk", "juice", "wine", "water", "soup",
        "flower", "rose", "lily", "tulip", "daisy", "sunflower", "orchid",
        "tree", "oak", "pine", "maple", "willow", "bamboo", "palm",
        "leaf", "branch", "root", "seed", "fruit", "vegetable", "herb",
        "star", "moon", "sun", "planet", "comet", "meteor", "galaxy",
        "cloud", "rain", "snow", "thunder", "lightning", "rainbow", "wind",
        "shadow", "dream", "memory", "secret", "mystery", "riddle", "puzzle",
        "story", "legend", "myth", "fairy", "ghost", "spirit", "angel"
    ]

    // MARK: - Plural Nouns

    static let pluralNouns: [String] = [
        "elephants", "tigers", "monkeys", "dolphins", "penguins", "cats",
        "dogs", "horses", "birds", "fish", "rabbits", "foxes", "wolves",
        "bears", "lions", "eagles", "owls", "butterflies", "bees", "ants",
        "wizards", "witches", "knights", "pirates", "sailors", "soldiers",
        "doctors", "teachers", "artists", "musicians", "dancers", "singers",
        "mountains", "rivers", "lakes", "forests", "gardens", "castles",
        "towers", "bridges", "temples", "libraries", "theaters", "schools",
        "tables", "chairs", "books", "letters", "maps", "keys", "locks",
        "swords", "shields", "arrows", "hammers", "crystals", "diamonds",
        "crowns", "rings", "treasures", "umbrellas", "hats", "boots",
        "apples", "oranges", "cherries", "flowers", "roses", "trees",
        "leaves", "stars", "moons", "planets", "clouds", "shadows", "dreams",
        "memories", "secrets", "mysteries", "riddles", "puzzles", "stories"
    ]

    // MARK: - Verbs (present tense)

    static let verbs: [String] = [
        "dances", "sings", "plays", "runs", "walks", "jumps", "flies",
        "swims", "climbs", "crawls", "sleeps", "wakes", "dreams", "thinks",
        "speaks", "whispers", "shouts", "laughs", "cries", "smiles",
        "watches", "listens", "waits", "searches", "finds", "hides",
        "shows", "teaches", "learns", "reads", "writes", "draws", "paints",
        "builds", "creates", "destroys", "fixes", "breaks", "opens", "closes",
        "starts", "stops", "begins", "ends", "grows", "shrinks", "rises",
        "falls", "floats", "sinks", "spins", "turns", "rolls", "slides",
        "bounces", "crashes", "explodes", "melts", "freezes", "burns",
        "glows", "sparkles", "shines", "fades", "appears", "disappears",
        "arrives", "leaves", "returns", "travels", "explores", "discovers",
        "remembers", "forgets", "believes", "doubts", "hopes", "fears",
        "loves", "hates", "wants", "needs", "gives", "takes", "keeps",
        "loses", "wins", "tries", "succeeds", "fails", "helps", "hurts"
    ]

    // MARK: - Past Tense Verbs

    static let pastVerbs: [String] = [
        "danced", "sang", "played", "ran", "walked", "jumped", "flew",
        "swam", "climbed", "crawled", "slept", "woke", "dreamed", "thought",
        "spoke", "whispered", "shouted", "laughed", "cried", "smiled",
        "watched", "listened", "waited", "searched", "found", "hid",
        "showed", "taught", "learned", "read", "wrote", "drew", "painted",
        "built", "created", "destroyed", "fixed", "broke", "opened", "closed",
        "started", "stopped", "began", "ended", "grew", "shrank", "rose",
        "fell", "floated", "sank", "spun", "turned", "rolled", "slid",
        "bounced", "crashed", "exploded", "melted", "froze", "burned",
        "glowed", "sparkled", "shone", "faded", "appeared", "disappeared",
        "arrived", "left", "returned", "traveled", "explored", "discovered",
        "remembered", "forgot", "believed", "doubted", "hoped", "feared",
        "loved", "hated", "wanted", "needed", "gave", "took", "kept",
        "lost", "won", "tried", "succeeded", "failed", "helped", "hurt"
    ]

    // MARK: - Adverbs

    static let adverbs: [String] = [
        "quietly", "loudly", "softly", "gently", "roughly", "quickly",
        "slowly", "carefully", "carelessly", "gracefully", "awkwardly",
        "happily", "sadly", "angrily", "calmly", "nervously", "bravely",
        "fearfully", "proudly", "humbly", "eagerly", "reluctantly",
        "patiently", "impatiently", "silently", "noisily", "secretly",
        "openly", "honestly", "mysteriously", "magically", "suddenly",
        "gradually", "constantly", "occasionally", "frequently", "rarely",
        "always", "never", "sometimes", "often", "usually", "hardly",
        "completely", "partially", "entirely", "mostly", "nearly", "almost",
        "exactly", "approximately", "barely", "slightly", "greatly",
        "deeply", "highly", "lowly", "brightly", "dimly", "warmly", "coldly",
        "sweetly", "bitterly", "smoothly", "roughly", "sharply", "dully"
    ]

    // MARK: - Prepositions

    static let prepositions: [String] = [
        "under", "over", "above", "below", "beside", "between", "behind",
        "before", "after", "inside", "outside", "within", "without",
        "through", "across", "around", "along", "toward", "against",
        "upon", "beneath", "beyond", "during", "until", "since", "near"
    ]
}
