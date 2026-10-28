import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/mail/mail_source.dart';
import 'package:piuma_mail/mail/recipient_suggestions.dart';

void main() {
  test(
    'device accounts and aliases supplement the existing people query',
    () async {
      final source = DemoMailSource();
      final own = await source.suggestRecipients('matteo@');
      expect(
        own.map((p) => p.email),
        containsAll(['matteo@posta.it', 'matteo@studio.it']),
      );
      expect(own.every((p) => p.accountColor != null), isTrue);
      await source.addAlias(2, 'projects@studio.it');
      expect(
        (await source.suggestRecipients('projects')).single.email,
        'projects@studio.it',
      );
      expect(
        (await source.suggestRecipients('lu')).single.email,
        'luca@studio.it',
      );
      expect(
        (await source.suggestRecipients('lu')).single.accountColor,
        source.accounts.firstWhere((account) => account.id == 2).color,
      );
    },
  );

  test(
    'suggestions preserve ranking, deduplicate addresses and respect limits',
    () {
      final source = DemoMailSource();
      final account = source.accounts.first;
      final result = recipientSuggestions(
        'mat',
        [
          Contact(
            name: 'Known name',
            email: account.email.toUpperCase(),
            writtenTo: true,
          ),
          Contact(name: 'Duplicate', email: account.email),
        ],
        source.accounts,
        {},
        limit: 1,
      );
      expect(result, hasLength(1));
      expect(result.single.name, 'Known name');
      expect(result.single.writtenTo, isTrue);
      expect(result.single.accountColor, account.color);
      expect(recipientSuggestions(' ', result, source.accounts, {}), isEmpty);
      expect(
        recipientSuggestions('mat', result, source.accounts, {}, limit: 0),
        isEmpty,
      );
    },
  );
}
