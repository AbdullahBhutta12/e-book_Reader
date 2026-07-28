/// The ways the library screen can sort its book list.
///
/// A plain enum, same reasoning as `TtsPlaybackState` — these three
/// values carry no data of their own, so there's nothing an enhanced
/// enum would buy here.
enum LibrarySortOrder { recentlyOpened, title, recentlyImported }
