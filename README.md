# 지민 — 먼저 전화해 주는 iPhone AI 동반자

SwiftUI iPhone 앱(iOS 17.4 이상), 사용 시간 감지 확장 기능, TypeScript 통화 서버를 함께 구현한 독립 MVP 원형입니다. 사용 시간은 연락할 타이밍을 정합니다. 전화는 매번 다른 엉뚱한 질문·상상 이야기·장난으로 시작하고, 사용자의 답에 따라 한국어 음성 대화를 이어갑니다.

**지금 자동 전화 전송은 기본적으로 꺼져 있습니다.** Apple이 사용 시간 감지에서 나온 최소 통화 신호의 외부 전송을 허용하는지 확인하기 전에는, 감지는 기기에만 기록하고 AI 통화는 사용자가 직접 요청합니다. 설정의 ‘먼저 전화하기’를 켜도 이 승인 잠금을 우회할 수 없습니다.

## 만들어진 기능

- 성격 3가지, 기본 이름 ‘지민’, 이름·목소리·호칭 변경, 말투 음성 예시, 첫 약속과 권한 안내, 시험 통화.
- **AI / 우리 / 설정** 화면. 집중 점수 대신 캐릭터, 최근 통화, 확인된 기억을 보여줍니다.
- FamilyControls의 실제 앱 선택, 앱별 하루 누적 한도, 자정 기준 갱신, DeviceActivityMonitor 확장 기능, 기기 안의 감지 기록.
- 첫 전화를 놓친 뒤 **그 앱을 추가로 사용한 시간**을 별도로 세는 재전화. 기본 20분, 하루 앱마다 최대 2회, 받았으면 그날 해당 앱에서 자동 전화 중단.
- CallKit 수신·받기·거절·끊기, PushKit 등록과 수신, APNs VoIP 전송, 오래된 요청·중복·통화 중 추가 이벤트 처리.
- 서버가 `gpt-live-1` WebRTC 세션을 만들고, `gpt-6-luna` Responses 작업 모델이 기억·동행·연락 중단 요청을 처리합니다. 서버가 API 키를 보관하며, Live는 자연스러운 양방향 음성 대화를 맡습니다.
- 새 전화마다 무작위 이야기 소재를 선택합니다. 최근 12개 소재와 바로 직전 장르를 피하고, 같은 전화의 재요청·조회·음성 세션에는 같은 소재를 유지합니다. 기본은 가벼운 1~2분 대화이며, 동행은 사용자가 먼저 원할 때 선택합니다.
- 기억 후보와 확정 기억을 구분합니다. 확인 버튼 또는 방금 확인 질문 뒤의 명시적인 “기억해 줘/저장해 줘” 음성 동의만 저장합니다. 수정·삭제는 다음 통화에 반영됩니다.
- ‘오늘은 쉬기’와 분명한 음성 연락 중단 요청. 다음 현지 날짜에 자동으로 해제됩니다.
- 통화 후 앱 사용 중단·다음날 전화 의향을 **자기보고**로 수집합니다. 수신이나 연결 성공을 행동 변화로 간주하지 않습니다.

## 지금 어디까지 확인했나요?

컴파일과 자동 검사는 실제 iPhone 동작, Apple 승인, 사용자 효과를 대신하지 않습니다. 최신 판정은 [구현·검증 보고서](docs/IMPLEMENTATION_REPORT.md)에 분리해 기록했습니다. 실기기 시험은 [검증표](docs/DEVICE_TEST_MATRIX.md), Apple 문의 준비 내용은 [확인 요청 문안](docs/APPLE_APPROVAL_PACKET.md)을 사용하세요.

## 폴더 안내

| 위치 | 역할 |
|---|---|
| `ios/Jimin.xcodeproj` | Xcode에서 여는 iPhone 앱 프로젝트 |
| `ios/App` | 세 화면, 온보딩, CallKit·PushKit, WebRTC, 기억 동의 처리 |
| `ios/MonitorExtension` | 앱이 닫힌 동안 사용 한도를 감지하는 확장 기능 |
| `ios/Shared` | 기기 안의 저장소, 사용 시간 감지 등록, 승인 후 전송 경로 |
| `Core` | 앱·확장 기능이 함께 사용하는 통화 규칙과 검사 |
| `server` | 기기 등록, 통화 요청, APNs, OpenAI 음성 연결, 통화 결과 |

## Mac에서 처음 실행하기

Xcode 15.3 이상(검증 환경: Xcode 26.0), Node.js 22 이상이 필요합니다. 프로젝트 파일은 이미 포함되어 있으며, 구조를 바꿨을 때만 XcodeGen으로 다시 생성하면 됩니다.

1. `ios/Jimin.xcodeproj`를 Xcode로 엽니다. `Jimin` 실행 대상을 고르고 iPhone 시뮬레이터에서 실행합니다. 시뮬레이터는 화면·저장 흐름을 확인하는 용도이며 Screen Time·APNs 실기기 검증을 대신하지 않습니다.
2. 터미널에서 서버 폴더로 이동해 준비합니다. 이미 실행 중인 시험 서버가 있으면 먼저 종료합니다.

   ```sh
   cd /Users/isihyeon/Desktop/Jimin/server
   npm ci
   npm run build
   npm run setup:openai
   ```

3. [이 Mac의 비공개 키 설정 화면](http://127.0.0.1:8788)을 엽니다. 본인의 OpenAI API 키를 비밀번호 입력칸에 붙여 넣고 ‘저장하고 연결 확인’을 누릅니다. **키를 채팅에 보내지 마세요.** 이 화면은 외부에 공개하지 않으며 이 Mac에서만 열립니다.
4. 설정 도구가 임의 연결 코드를 만들고 `.env`를 소유자만 읽고 쓸 수 있도록 저장합니다. 입력한 키로 `gpt-live-1`과 작업 모델 `gpt-6-luna`의 조회 접근을 확인한 뒤 서버를 재시작합니다. API 키·연결 코드·서버 데이터는 Git에서 제외됩니다. 모델 조회 인증 성공은 통화나 API 잔액의 증명이 아니므로 실제 음성 연결은 따로 시험해야 합니다. API 키가 없으면 등록만 시험할 수 있고 실제 AI 음성은 설정 오류로 끝납니다.
5. 앱을 설치한 iPhone 시뮬레이터 한 대가 켜져 있으면 설정 도구가 로컬 연결을 요청합니다. 필요하면 설정 화면의 ‘시뮬레이터 앱에 서버 연결’을 누르고 시스템의 ‘지민에서 열기’를 선택하세요. 이미 연결된 앱은 유지합니다. 직접 연결하려면 앱의 ‘시험 서버 연결’에 `http://127.0.0.1:8787`과 `.env`의 `REGISTRATION_CODE`를 입력할 수 있습니다. **OpenAI 키를 앱에 입력하지 않습니다.** 실기기에는 유효한 인증서가 있는 **HTTPS** 서버 주소를 사용하세요.
6. 마이크를 허용하고 ‘시험 전화 받기’ 또는 홈의 ‘대화하기’를 누릅니다. 수동 시험은 앱에서 CallKit 수신을 요청하므로 APNs 키 없이 시작할 수 있습니다. 실제 백그라운드 VoIP 수신 시험은 승인된 자동 경로와 APNs 설정이 필요합니다.

서버 연결 전 말투 미리 듣기는 **아이폰 기본 음성**이라고 표시합니다. 서버 연결 후 예시는 `gpt-4o-mini-tts`로 만들며, 실제 통화는 `gpt-live-1`을 사용합니다. 예시 음성이 실제 Live 통화 음색과 같다고 가정하지 마세요. 한국어 음질과 실제 통화 음색은 실기기에서 확인해야 합니다.

`gpt-live-1`은 연결 시간으로 과금되고 작업 모델 호출은 별도로 과금됩니다. 서버는 종료 시 Live가 돌려준 실제 연결 초 수를 통화 기록에 남기며, 종료 확인이 오지 않으면 사용량을 확정하지 않습니다. 20분 동행은 긴 무음 구간도 포함하므로 실제 비용과 연결 유지 상태를 시험해야 합니다.

## 실기기 서명과 사용 시간 감지

자신의 Apple Developer 팀을 Xcode의 Signing에 지정하고, 앱·확장 기능의 Bundle ID와 App Group, 공유 Keychain 그룹을 자신의 등록 값으로 맞추세요. 현재 예시 값은 `com.jimin.mvp`, `com.jimin.mvp.monitor`, `group.com.jimin.mvp`입니다. APNs의 Bundle ID도 같은 앱 값을 써야 합니다.

`Jimin`과 `JiminMonitor` 양쪽에 Family Controls를 설정하고, App Groups와 공유 Keychain 접근 권한을 맞춥니다. 앱에는 Push Notifications, Audio/VoIP Background Modes도 설정되어 있습니다. Family Controls **배포** 권한은 앱과 확장 기능 각각 Apple에게 승인받아야 TestFlight 통합 시험으로 진행할 수 있습니다.

아이폰의 실제 앱 목록을 여는 데는 먼저 FamilyControls 권한이 필요하므로, 온보딩의 앱 선택 버튼에 짧은 약속과 권한 설명을 붙이고 그 시점에 시스템 허용 화면을 엽니다. 이어서 한도·먼저 전화하는 약속·마이크/알림·시험 통화를 진행합니다. 앱 이름을 보고 선택 토큰을 임의로 추정하지 않습니다. 개별 앱만 선택하며 초기 원형은 최대 10개로 제한합니다.

감지 권한을 아직 준비하지 못했으면 ‘사용 시간 설정은 나중에 · 수동 통화부터 시험하기’를 선택할 수 있습니다. 실제 음성 연결 시험에는 Screen Time 권한이 필요하지 않습니다. 감지 앱은 이후 설정에서 고를 수 있습니다.

한도는 **연속 사용이 아니라 하루 누적 사용**입니다. 일부 앱의 연결된 웹사이트 사용도 Apple의 집계에 포함될 수 있고, 쇼츠와 메시지를 구분하지 않습니다. 원본 토큰이나 사용 시간 보고서를 서버로 보내지 않습니다.

## Apple 확인 후의 자동 통합 시험

**이 단계를 실행할 수 있다는 사실이 Apple 허용의 증거는 아닙니다.** 먼저 [Apple 확인 요청 문안](docs/APPLE_APPROVAL_PACKET.md)의 정확한 데이터 흐름에 대한 서면 답변을 확보하고 기록합니다. 그 뒤에만 다음을 함께 설정합니다.

- 서버 `.env`: `AUTO_CALL_APPROVED=true`, 실제 `APPLE_APPROVAL_REFERENCE`, APNs `.p8` 파일 경로·Key ID·Team ID·Bundle ID·환경.
- 앱과 확장 기능: `AUTOMATION_APPROVED=YES`, 같은 승인 근거를 `AUTO_CALL_APPROVAL_REFERENCE`에 설정한 뒤 다시 빌드·서명.
- Debug는 APNs sandbox, Release/TestFlight는 production입니다. 배포 서명과 APNs 환경을 각각 확인합니다.

사용 시간 이벤트에서 나오는 전송 내용은 임의 요청 ID, 이벤트 시각, 자동 요청 구분뿐입니다. **이 신호도 사용 시간에서 파생되므로**, 최소화했다고 허용된 것으로 판단하지 않습니다. 확장 기능의 백그라운드 전송은 지연될 수 있고, 서버는 60초가 지난 요청을 버립니다. APNs 수신도 운영체제·네트워크·방해금지 설정의 영향을 받습니다.

## 자동 검사

```sh
cd /Users/isihyeon/Desktop/Jimin/Core
swift test
cd /Users/isihyeon/Desktop/Jimin/server
npm test
npm run typecheck
npm run build
```

시뮬레이터용 앱과 확장 기능 빌드:

```sh
cd /Users/isihyeon/Desktop/Jimin/ios
xcodebuild -project Jimin.xcodeproj -scheme Jimin -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath ../DerivedData CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build
```

시뮬레이터에서도 Keychain 저장을 시험하려면 위의 ‘로컬 실행용 서명’이 필요합니다. `CODE_SIGNING_ALLOWED=NO` 빌드는 화면만 열려도 인증 정보 저장이 실패할 수 있습니다. 실기기 서명과 Family Controls 배포 승인은 별도입니다. 시뮬레이터의 앱 설정은 서명 방식 변경 후에도 유지되도록 앱 컨테이너에 저장합니다.

## 원형의 운영 조건

서버는 단일 프로세스용 파일 저장소입니다. 여러 서버를 동시에 실행하거나 실제 이용자를 늘리기 전에는 데이터베이스, 기기별/요청별 잠금, 인증 수명, 관측·장애 처리를 보강해야 합니다. 기본 주소는 localhost이며 외부 공개·배포는 이번 작업에 포함하지 않습니다.

앱의 토큰·한도·당일 시도 기록·기억은 App Group에, 서버 인증 정보는 Keychain에 보관합니다. 서버에는 사용자가 확인한 기억과 캐릭터 설정, 통화 운영 기록을 보관합니다. 종료된 통화의 별도 기억 스냅샷은 제거합니다. 녹음·전체 대화 전문은 앱이나 이 서버에 저장하지 않습니다. OpenAI에서의 데이터 처리는 사용하는 계정과 서비스 조건에 따라 따로 확인해야 합니다. 앱의 연결 삭제 기능은 해당 기기의 서버 데이터와 인증을 삭제합니다.

네이티브 WebRTC는 [stasel/WebRTC 153.0.0](https://github.com/stasel/WebRTC/tree/153.0.0)의 공개 패키지로 고정했습니다. 이 패키지는 OpenAI 공식 iOS SDK가 아니며 Google WebRTC 바이너리를 제공합니다. 캘린더, Android, 결제는 구현 범위에서 제외했습니다.
