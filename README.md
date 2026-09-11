# 사이역 (RememberSubway)

대한민국 도시철도 역 이름을 외우고 가까운 사람들과 대결하는 iOS 26+ SwiftUI 게임입니다. 한국어 앱 이름은 `사이역`, 영어 앱 이름은 `RememberSubway`입니다.

- `싱글플레이`: 지역 전체 또는 노선을 선택해 이전 역과 다음 역 사이의 역을 맞히는 상시 도전. 첫·마지막 역도 출제되며 없는 방향은 `이전 역 없음`·`다음 역 없음`으로 표시
- `멀티플레이`: 근처의 iPhone 2~8대가 같은 10문제를 푸는 실시간 점수전

싱글플레이는 주차별로 초기화되지 않습니다. 최고 기록은 콘텐츠 버전과 선택한 지역·노선 범위별로 기기에 저장됩니다. 모든 문제의 기본 정답 점수는 100점이며, 초성 힌트 사용 시 50점입니다. 문제당 15초가 주어지고 남은 시간이 10초 미만이면 초당 10%씩 점수가 감소합니다.

## 실행

```sh
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project RememberSubway.xcodeproj -scheme RememberSubway \
  -destination 'platform=iOS Simulator,name=iPhone 16e' test
```

프로젝트 생성에는 [XcodeGen](https://github.com/yonaskolb/XcodeGen)을 사용합니다. 앱은 노선 JSON과 기록을 기기에 보관하므로 Game Center 연결 없이도 싱글플레이를 이용할 수 있습니다. 멀티플레이는 Network framework와 Bonjour를 사용하며 인터넷이나 Game Center 로그인이 필요하지 않습니다.

## 노선 데이터

- 앱 데이터: `RememberSubway/Resources/transit_data.json`
- 독립 검증: `swift Tools/validate_transit_data.swift`
- 앱 시작 시에도 동일한 참조 무결성을 검사합니다.

번들 데이터에는 수도권의 코레일 광역전철·민자 노선과 각 지역 도시철도 노선이 포함됩니다. `contentVersion`이 다른 앱끼리는 멀티플레이 참가를 차단하므로 노선 데이터를 바꾸어 출시할 때 두 버전의 호환성을 확인해야 합니다.

## 근처 대전 설정

- Bonjour 서비스 타입: `_rsubway._tcp`
- 로컬 네트워크 권한은 사용자가 방 만들기 또는 근처 방 찾기를 선택할 때 요청합니다.
- 연결 메시지는 임시 키 합의 후 CryptoKit으로 암호화합니다.
- 실제 출시 검증은 iPhone 2대 이상에서 Wi-Fi 연결 상태와 Wi-Fi 없이 peer-to-peer 상태를 모두 확인합니다.

## Game Center 설정

App Store Connect에서 다음 식별자를 생성해야 실제 제출이 활성화됩니다.

- 지역 전체 상시 리더보드: `kr.co.remembersubway.single.region.{region_id}.v1`
- 노선별 상시 리더보드: `kr.co.remembersubway.single.line.{line_id}.v1`

리더보드 ID의 하이픈은 밑줄로 변환합니다. 예를 들어 서울 4호선은 `kr.co.remembersubway.single.line.seoul_4.v1`입니다. 앱에 포함된 모든 지역과 노선 ID를 App Store Connect에 상시 리더보드로 등록해야 실제 순위 제출과 조회가 동작합니다. 기본 호환 ID는 `kr.co.remembersubway.single.v1`입니다.

인증이나 네트워크가 실패해도 싱글플레이는 계속되며 최고 점수는 SwiftData에 제출 대기 상태로 저장됩니다. 제거된 일반 학습 모드의 업적은 더 이상 제출하지 않습니다.

### 리더보드 API 일괄 등록

`Tools/register_game_center_leaderboards.py`는 위의 지역·노선 목록을 읽어 App Store Connect API에 일괄 등록합니다. 기본 실행은 미리보기이며, 실제 등록에는 API 키와 Game Center detail ID가 필요합니다.

```bash
python3 -m pip install cryptography
export ASC_ISSUER_ID="App Store Connect Issuer ID"
export ASC_KEY_ID="API Key ID"
export ASC_PRIVATE_KEY_PATH="/안전한/경로/AuthKey_XXXXXXXXXX.p8"
export ASC_GAME_CENTER_DETAIL_ID="Game Center detail resource ID"

# 등록 목록만 확인
python3 Tools/register_game_center_leaderboards.py

# 실제 생성 및 제목 현지화(37개)
python3 Tools/register_game_center_leaderboards.py --apply --localize
```

기본적으로 현재 사용하는 지역·노선별 37개(지역 5개 + 노선 32개)를 등록합니다. `--localize`는 한국어·영어 제목과 설명을 추가하거나 기존 값을 수정합니다. API 키 파일은 저장소에 커밋하거나 채팅으로 공유하지 마세요. 생성 요청은 Apple의 [`POST /v1/gameCenterLeaderboards`](https://developer.apple.com/documentation/appstoreconnectapi/post-v1-gamecenterleaderboards)를 사용합니다.
