# UI redesign v2 — 2026-09-29

## Reference review

Reviewed the current published App Store screenshots, not installed competitor builds:

- [Character.AI](https://apps.apple.com/us/app/character-ai-chat-talk-text/id1671705818): immersive character art in voice calls, spare circular call controls, dark browsing chrome.
- [Nomi](https://apps.apple.com/us/app/nomi-ai-companion-with-a-soul/id6450270929): compact character identity, readable conversational hierarchy, restrained purple accents on dark conversation screens.
- [러비더비](https://apps.apple.com/kr/app/id6468766519): character-first relationship presentation and warm accents. Currency, points and relationship progression are outside this product's scope.

The previous light blue UI separated the portrait, name, greeting and call action into unrelated blocks. Too many captions competed with the character. The redesign joins these into one voice-first scene, with a consistent quiet shell for memories and settings. Competitor artwork is not reused.

## Tokens and layout, before implementation

| Token | Value | Purpose |
|---|---|---|
| Night | #18151F | App background and image fade |
| Room | #27232F | Settings groups and input surfaces |
| Pearl | #F7F1FA | Main text |
| Mist | #B4AABD | Supporting text |
| Lilac | #CCBCF4 | Call action and selected states |
| Apricot | #F0BDA7 | Small relationship accent |

Use the native Korean system font for legibility and Dynamic Type. 28pt-equivalent title, 20pt scene quote, 17pt body, 13pt secondary text. Display text is left aligned; call status and call controls are centered. Touch targets are at least 44pt. Screen gutters 24pt, section gap 24–28pt. Do not show an online dot or speaking animation without a real corresponding state.

```
AI home                         Voice call
┌──────────────────────┐        ┌──────────────────────┐
│ 지민              ⚙  │        │     AI 음성 통화      │
│ 솔직한 장난꾸러기     │        │        지민           │
│                      │        │   actual call state  │
│   full character     │        │                      │
│   scene in a room    │        │    character scene   │
│                      │        │                      │
│ 짧은 캐릭터 한마디    │        │ consent / quiet time │
│                      │        │ only when applicable │
│ [   전화로 이야기   ]│        │    mute     end      │
│ 실제 최근 통화        │        │   오늘 연락 쉬기      │
│   AI   우리   설정    │        └──────────────────────┘
└──────────────────────┘
```

Our screen shows one chosen companion, not a marketplace grid. A fictional adult character illustration provides the memorable element; surrounding controls stay quiet. No score, level, fake conversation, fabricated memory or live availability is added. Home's short line is persona presentation, not a generated message history. Connection requirements remain accurate.

## Plan critique

Merely changing white cards to purple cards would reproduce the previous layout. Therefore the home loses its isolated photo tile and marketing heading: portrait, quote and voice action form one continuous scene. Settings keep functional grouped rows rather than decorating every item with an identical card. Memory content uses a journal layout. Gradients only provide image-to-background continuity and text contrast, not decorative washes. The quiet interface supports a surprising conversation without turning the UI into another feed.

## Validation

### 적용 및 확인

- 홈을 전체 캐릭터 장면으로 바꾸고 이름, 말투의 한마디, 전화 버튼을 연결했다. 실제 통화 준비 상태와 최근 기록만 표시한다. 전화 버튼과 탭은 스크롤 내용과 별도의 공간을 가지므로 큰 글자에서도 표시된다.
- ‘우리’는 함께한 날짜를 작게 보여주고, 확인한 기억을 글 목록으로 구성한다. 빈 목록, 입력 화면, 빈 내용의 저장 비활성화, 입력 후 저장 활성화, 취소 후 빈 목록 유지까지 실제로 확인했다. 시험 문장은 저장하지 않았다.
- 설정, 성격 선택, 목소리 이름표, 연결 안내와 첫 설정에 같은 색과 글자 체계를 적용했다. 목소리와 성격 편집은 기존의 임시 편집과 완료/취소 방식이 유지된다.
- 수신 화면은 전체 캐릭터 장면과 큰 두 버튼으로 다시 구성했다. 실제 로컬 서버에 수동 요청을 보낸 뒤 개발용 앱 내부 화면이 나타나는 것과 거절 후 홈 복귀를 확인했다. OpenAI 음성 연결, PushKit/CallKit의 실제 시스템 수신 성공을 뜻하지 않는다.
- 개발용 수신 시험은 Debug 시뮬레이터에서만 제공한다. 화면에 개발용임을 명시하고 실제 수동 서버 요청을 사용한다. 이 경로는 CallKit을 건너뛰며, 일반 수동 전화와 VoIP 수신은 기존 CallKit 경로를 사용한다. 시뮬레이터의 일반 경로에서 요청이 약 2초 후 declined로 종료되는 것을 관찰했으나 원인은 확인하지 않았다.
- iPhone 17 Pro의 기본 글자와 accessibility-large에서 홈의 전화 버튼과 탭 표시를 확인했다. 시험 후 기본 large 크기로 복구했다. 전체 최대 글자 크기, VoiceOver 실제 읽기, 모든 설정 항목의 스크롤 조작은 별도 확인이 필요하다.
- 별도 iPhone SE 3세대에서 첫 설정 화면과 하단 버튼의 표시를 확인했다. 중복 단계 이름을 없애고 제목 크기를 줄였다. 여섯 단계 전체의 조작 완료를 확인한 것은 아니며, 시험 기기는 종료했다.
- 주요 단색 영역 대비: 본문/바탕 16.23:1, 보조 글자/기능 바탕 6.89:1, 전화 버튼 글자/버튼 10.35:1. 인물 위의 글자에는 어두운 페이드를 적용했다.
- 앱과 감지 확장 기능의 시뮬레이터 빌드 passed. 아이콘 1024×1024, 알파 없음. 시작 화면 바탕도 앱의 어두운 색으로 맞췄다.

시뮬레이터 화면 표시는 실기기 사용 시간 권한·자동 감지·전화 수신·실제 한국어 음성·Apple 허용·사용자 행동 변화와 별도로 판정한다. 서버의 실제 음성 키는 입력 대기이며 자동 전화 승인 플래그는 꺼져 있다.

확인 화면: [홈](evidence/ui-v2-home.png), [우리](evidence/ui-v2-together.png), [기억 작성](evidence/ui-v2-memory-editor.png), [설정](evidence/ui-v2-settings.png), [성격 선택](evidence/ui-v2-character.png), [앱 내부 수신](evidence/ui-v2-incoming.png), [큰 글자의 홈](evidence/ui-v2-home-large-type.png), [작은 아이폰의 첫 설정](evidence/ui-v2-onboarding-small.png).

참고 화면: [Character.AI 공개 App Store 캡처](design/references/character-ai-app-store.png). 캐릭터 원본과 정확한 생성 프롬프트: [이미지 제작 기록](CHARACTER_SCENE_V2.md).
