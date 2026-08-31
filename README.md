# 역순서

대한민국 도시철도 역 이름을 외우고 가까운 사람들과 대결하는 iOS 26+ SwiftUI 게임입니다.

- `싱글플레이`: 이전 역과 다음 역을 보고 가운데 역을 맞히는 지역별 주간 도전
- `멀티플레이`: 근처의 iPhone 2~8대가 같은 10문제를 푸는 실시간 점수전

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

- 7일 반복 리더보드: `kr.co.remembersubway.weekly.v1`
인증이나 네트워크가 실패해도 싱글플레이는 계속되며 주간 최고 점수는 SwiftData에 제출 대기 상태로 저장됩니다. 제거된 일반 학습 모드의 업적은 더 이상 제출하지 않습니다.
