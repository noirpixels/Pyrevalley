extends RefCounted

# Word lists for name_filter.gd. Edit freely: one lowercase word per entry,
# letters only. A GDScript file rather than a .txt so exported builds
# always include it (Godot leaves plain text files out of exports).

# Blocked wherever they appear in a name, even inside other words. Only
# words that almost never turn up inside innocent ones belong here.
const ANYWHERE = [
	"fuck", "shit", "cunt", "bitch", "whore", "slut", "twat", "wank", "bollock",
	"asshole", "arsehole", "bastard", "motherf", "dickhead", "jackass", "jerkoff",
	"nigger", "nigga", "niggr", "faggot", "fagot", "retard", "tranny", "wetback",
	"kike", "beaner", "chingchong", "raghead", "towelhead", "sandnigger",
	"nazi", "hitler", "heilhitler", "siegheil", "kkk", "whitepower",
	"rapist", "pedophile", "paedophile", "molest", "porn", "penis", "vagina",
	"dildo", "jizz", "blowjob", "handjob", "cumshot", "orgasm",
	"pussy", "boner", "erection", "testicle", "killyourself", "suicide",
]

# Blocked only as a whole name or a whole word in it ("Cassandra" and
# "Grassy" are fine; "Big Ass" isn't)
const WHOLE = [
	"ass", "arse", "cock", "dick", "prick", "piss", "tit", "tits", "boob", "boobs",
	"cum", "sex", "anal", "anus", "rape", "fag", "spic", "chink", "gook", "coon",
	"dyke", "paki", "pedo", "nonce", "kys", "hoe", "thot", "milf", "damn", "horny",
]

# Innocent words that contain a blocked one; taken out before checking
const ALLOW = [
	"scunthorpe", "therapist", "shiitake", "retardant", "pussycat",
	"cockpit", "peacock", "hancock", "cocktail", "dickens", "passion",
	"assassin", "class", "grass", "bass", "compass", "analyst", "titan",
	"arsenal", "sussex", "essex", "torpedo", "document", "cucumber",
	"circumference", "shitake", "penistone", "matsushita",
]

# Names nobody may take
const RESERVED = [
	"host", "admin", "administrator", "moderator", "mod", "server", "system",
	"embershade", "embervale", "developer", "dev", "staff", "official",
]
