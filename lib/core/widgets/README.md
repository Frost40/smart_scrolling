# LEGO box: pieces used by two or more screens

Read this before building a piece. Reuse or extend; never copy.

- `card_media.dart`: CardMedia. User-started video/audio with VTT captions, poster, resume and automatic pause when leaving; mediaPlaybackChanges pauses players on navigation or another Play.
- `media_controls.dart`: MediaControls. Labeled play/pause, accessible seek slider and elapsed/total time for both players.

- `page_list.dart`: PageList. A centered, width-limited scrolling page that holds a screen's sections; give it a controller inside a draggable sheet.
- `heading.dart`: Heading. A section or screen title in the theme's headline style.
- `format_selector.dart`: FormatSelector. The "Mix or one format" menu (Discover and Practice); give it the stored values.
- `discover_card_view.dart`: DiscoverCardView, CardFlip, CardFront and CardImage. One full Discover card: a format-colored band, badge and title; tap to flip it in 3D (Discover, Source page, Library, Practice's "Testing" dialog).
- `card_back.dart`: CardBack. The compact back of a Discover card: back text, location, source, level, attributed text sharing, Source page and Report a problem.
- `hold_to_refresh.dart`: HoldToRefresh and RefreshBadge. Wrap a feed list: on the top card, pull down and hold for `AppDurations.refreshHold`, or pull hard, to reload; a round badge follows the finger (Discover, Practice, Library).
- `report_dialog.dart`: ReportDialog and showReportDialog(). The "Report a problem" message form (Discover, Source page).
- `topic_chips.dart`: TopicChips, TopicArea and TopicChip. One card per main area: its name as title, an "All" chip for the whole area, its sub-topics as one gliding row inside; areas without sub-topics share one card (Onboarding, Settings).
- `auto_scroll_row.dart`: AutoScrollRow. A sideways row that glides to its end and back by itself when too wide; a touch stops it until a few idle seconds pass; still under reduce motion or TalkBack (topic cards).
- `related_cards.dart`: RelatedCards. Published See also links; card backs and source pages supply navigation.
- `edit_text_dialog.dart`: EditTextDialog. Collection name and private note editor; keeps drafts and errors visible until saved.
- `format_badge.dart`: FormatBadge. A format's icon in a soft circle of its color, with an optional label (cards, Progress).
- `enter_in.dart`: EnterIn. Fades a child in while it rises a little, once; nothing under reduce motion (feeds, empty states, Welcome).
- `section_card.dart`: SectionCard. A rounded card grouping one section, with optional icon and title (Settings, Progress, Account, Explore, Onboarding).
- `empty_art.dart`: EmptyArt and EmptyArtKind. Small pictures drawn in code from theme colors: cards, practice, library, search (empty states, Welcome, Start).
- `empty_state.dart`: EmptyState. Drawn picture, title, help line and actions for empty or finished feeds (Discover, Practice, Library, Explore).
