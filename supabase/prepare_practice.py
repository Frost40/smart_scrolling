"""Prepare ticket 06's emulator walkthrough; credentials stay on this computer.

Run: python supabase/prepare_practice.py
Then run integration_test/practice_walkthrough_test.dart with the usual defines.
Only agent@smartscrolling.test's sample-card activity is reset.
"""
import datetime
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.content.upload import Supabase  # noqa: E402


def main():
    test = json.loads((ROOT / '.env.test.json').read_text(encoding='utf-8'))
    if test['TEST_LOGIN_EMAIL'] != 'agent@smartscrolling.test':
        raise SystemExit('Refusing to prepare any account except the debug test login.')
    db = Supabase()
    source = db.select('sources', 'select=is_sample&id=eq.sample-curious-learner')
    if source != [{'is_sample': True}]:
        raise SystemExit('Sample box is missing; no activity changed.')
    login = db.call('POST', '/auth/v1/token?grant_type=password', {
        'email': test['TEST_LOGIN_EMAIL'], 'password': test['TEST_LOGIN_PASSWORD'],
    })
    if login['user']['email'] != 'agent@smartscrolling.test':
        raise SystemExit('Unexpected account; no activity changed.')
    card = 'sample-curious-learner/retrieval-practice'
    scope = f"user_id=eq.{login['user']['id']}&discover_card_id=eq.{card}"
    db.delete('practice_answers', scope)
    db.call('POST', '/rest/v1/rpc/like_card', {'p_card_id': card}, {
        'Authorization': 'Bearer ' + login['access_token'],
    })
    now = datetime.datetime.now(datetime.timezone.utc)
    db.update('likes', scope, {'review_level': 0, 'last_reviewed_at': None,
        'next_review_at': now.isoformat(), 'reviews_paused': False})
    rows = db.select('likes', 'select=review_level,next_review_at&' + scope)
    assert len(rows) == 1 and rows[0]['review_level'] == 0
    assert datetime.datetime.fromisoformat(rows[0]['next_review_at']) <= now
    print('Debug test Like prepared: level 0, due now (service-role setup).')


if __name__ == '__main__':
    main()
