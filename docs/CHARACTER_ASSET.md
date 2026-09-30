# 캐릭터 이미지 출처와 재생성

2026-09-29. OpenAI의 이 세션 내장 이미지 생성 도구 `image_gen`으로 새로 생성했습니다. 별도 서버 키나 이미지 API 호출은 사용하지 않았습니다. 외부 인물 사진을 가져오지 않았습니다.

최종 원본: `ios/App/Assets.xcassets/CharacterPortrait.imageset/portrait.png`.
아이콘: `ios/App/Assets.xcassets/AppIcon.appiconset/AppIcon.png`.
앱의 홈, 작은 아바타, 통화 화면에서 같은 원본을 사용합니다. 아이콘은 원본을 불투명 1024×1024 PNG로 규격 변환했습니다. `swift scripts/make-icon.swift ios/App/Assets.xcassets/AppIcon.appiconset/AppIcon.png`으로 다시 만들 수 있습니다.

생성 프롬프트:

```text
Use case: stylized-concept. Asset type: a bespoke character portrait for a polished Korean iPhone AI voice companion app named Jimin. Create a single square 2D editorial illustration of a clearly adult Korean woman in her mid-twenties, chest-up, front-facing, with a relaxed friendly closed-lip smile, subtle softly curved eyes, shoulder-length dark navy hair with an understated side part, wearing a simple cobalt-blue knit top. Mood: calm, approachable, mature, gently playful. Refined contemporary editorial illustration with clean confident curved shapes, restrained subtle paper texture on the subject, beautifully balanced facial features, elegant rather than cute. Solid very pale periwinkle background #E9EEFF, no scenery. Palette: deep navy hair #202C45, natural peach skin, blue #375BD2 knit. Center the portrait, generous margins, head and shoulders completely inside the frame, character occupies about 72 percent of the canvas; the lower chest ends at the bottom edge. High-quality visual suitable for a shipped app avatar and hero. No words, no UI, no logos, no floating decorations, no hearts, no stars, no phone props, no realistic photograph, no 3D plastic look, no anime, no oversized childlike eyes. The figure is an illustrated AI character.
```
