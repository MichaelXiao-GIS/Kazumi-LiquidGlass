import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';

Future<void> pumpPoster(WidgetTester tester, String url, double width) {
  return tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 2),
        child: Center(
          child: Hero(
            tag: url,
            flightShuttleBuilder: NetworkImgLayer.heroFlightShuttleBuilder,
            child: NetworkImgLayer(
              src: url,
              width: width,
              height: 200,
              type: 'bg',
            ),
          ),
        ),
      ),
    ),
  );
}

CachedNetworkImage posterImage(WidgetTester tester) =>
    tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));

void main() {
  const first = 'https://example.invalid/first.jpg';
  const second = 'https://example.invalid/second.jpg';

  testWidgets('resizes the poster immediately and decodes after resizing stops',
      (tester) async {
    await pumpPoster(tester, first, 100);
    expect(posterImage(tester).memCacheWidth, 200);

    await pumpPoster(tester, first, 120);
    expect(posterImage(tester).width, 120);
    expect(posterImage(tester).memCacheWidth, 200);
    await tester.pump(const Duration(milliseconds: 150));

    await pumpPoster(tester, first, 140);
    expect(posterImage(tester).width, 140);
    await tester.pump(const Duration(milliseconds: 199));
    expect(posterImage(tester).memCacheWidth, 200);
    await tester.pump(const Duration(milliseconds: 1));
    expect(posterImage(tester).memCacheWidth, 280);
    expect(posterImage(tester).memCacheHeight, isNull);
  });

  testWidgets('a replacement poster ignores the previous pending resize',
      (tester) async {
    await pumpPoster(tester, first, 100);
    final layer = tester.element(find.byType(NetworkImgLayer));
    await pumpPoster(tester, first, 130);
    await tester.pump(const Duration(milliseconds: 100));

    await pumpPoster(tester, second, 150);
    expect(tester.element(find.byType(NetworkImgLayer)), same(layer));
    expect(posterImage(tester).imageUrl, second);
    expect(posterImage(tester).memCacheWidth, 300);
    await tester.pump(const Duration(milliseconds: 100));
    expect(posterImage(tester).memCacheWidth, 300);
  });
}
