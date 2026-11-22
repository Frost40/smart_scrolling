import 'account_walkthrough_test.dart' as account;
import 'collections_walkthrough_test.dart' as collections;
import 'discover_walkthrough_test.dart' as discover;
import 'explore_walkthrough_test.dart' as explore;
import 'library_walkthrough_test.dart' as saved;
import 'media_walkthrough_test.dart' as media;
import 'more_practice_types_walkthrough_test.dart' as types;
import 'offline_practice_walkthrough_test.dart' as offline_practice;
import 'offline_walkthrough_test.dart' as offline;
import 'practice_walkthrough_test.dart' as practice;
import 'progress_data_walkthrough_test.dart' as progress;

// One entry point reuses the real UI scenarios; native share sheets are handled
// by tools/test_progress_data.ps1 with this file as its target.
void main() {
  account.main();
  explore.main();
  discover.main();
  saved.main();
  collections.main();
  practice.main();
  types.main();
  media.main();
  offline.main();
  offline_practice.main();
  progress.main();
}
