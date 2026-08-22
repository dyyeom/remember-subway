#!/usr/bin/env swift
import Foundation

struct Catalog: Encodable {
    let schemaVersion: Int
    let contentVersion: String
    let challengePoolVersion: String
    let dataAsOf: String
    let sources: [Source]
    let regions: [Region]
    let operators: [Operator]
    let stations: [Station]
    let lines: [Line]
    let routePatterns: [Pattern]
}

struct Source: Encodable { let title: String; let url: URL }
struct Region: Encodable { let id: String; let name: String; let sortOrder: Int }
struct Operator: Encodable { let id: String; let name: String }
struct Station: Encodable { let id: String; let name: String; let fullName: String?; let aliases: [String] }
struct Line: Encodable {
    let id: String
    let regionID: String
    let operatorID: String
    let name: String
    let shortName: String
    let colorHex: String
    let sortOrder: Int
}
struct Pattern: Encodable {
    let id: String
    let lineID: String
    let name: String
    let kind: String
    let stationIDs: [String]
}

struct LineSeed {
    let line: Line
    let prefix: String
    let patterns: [PatternSeed]
}

struct PatternSeed {
    let suffix: String
    let name: String
    let kind: String
    let stations: [String]

    init(_ name: String, _ stations: [String]) {
        self.init("main", name, stations)
    }

    init(_ suffix: String, _ name: String, kind: String = "main", _ stations: [String]) {
        self.suffix = suffix
        self.name = name
        self.kind = kind
        self.stations = stations
    }
}

// 역 표기는 `본역명|전체 공식 역명|쉼표로 구분한 검수 별칭` 형식이다.
func decodeStation(_ raw: String, id: String) -> Station {
    let fields = raw.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
    let name = fields[0]
    let fullName = fields.count > 1 && !fields[1].isEmpty ? fields[1] : nil
    let aliases = fields.count > 2 ? fields[2].split(separator: ",").map(String.init) : []
    return Station(id: id, name: name, fullName: fullName, aliases: aliases)
}

let regions = [
    Region(id: "capital", name: "수도권", sortOrder: 1),
    Region(id: "busan", name: "부산", sortOrder: 2),
    Region(id: "daegu", name: "대구", sortOrder: 3),
    Region(id: "gwangju", name: "광주", sortOrder: 4),
    Region(id: "daejeon", name: "대전", sortOrder: 5)
]

let operators = [
    Operator(id: "seoul-metro", name: "서울교통공사"),
    Operator(id: "metro9", name: "서울시메트로9호선"),
    Operator(id: "ui-line", name: "우이신설경전철"),
    Operator(id: "sillim-line", name: "남서울경전철"),
    Operator(id: "korail", name: "한국철도공사"),
    Operator(id: "shinbundang", name: "신분당선"),
    Operator(id: "arex", name: "공항철도"),
    Operator(id: "incheon-transit", name: "인천교통공사"),
    Operator(id: "busan-transit", name: "부산교통공사"),
    Operator(id: "bgl", name: "부산김해경전철"),
    Operator(id: "daegu-transit", name: "대구교통공사"),
    Operator(id: "gwangju-transit", name: "광주교통공사"),
    Operator(id: "daejeon-transit", name: "대전교통공사")
]

let lineSeeds: [LineSeed] = [
    LineSeed(
        line: Line(id: "seoul-1", regionID: "capital", operatorID: "seoul-metro", name: "서울 1호선", shortName: "1", colorHex: "0052A4", sortOrder: 1),
        prefix: "s1",
        patterns: [
            PatternSeed("서울역 → 청량리", [
                "서울역||서울", "시청", "종각", "종로3가", "종로5가", "동대문", "동묘앞", "신설동", "제기동", "청량리|청량리(서울시립대입구)"
            ]),
            PatternSeed("incheon", "연천 → 인천", [
                "연천", "전곡", "청산", "소요산", "동두천", "보산", "동두천중앙", "지행", "덕정", "덕계", "양주", "녹양", "가능", "의정부", "회룡", "망월사", "도봉산", "도봉", "방학", "창동", "녹천", "월계", "광운대", "석계", "신이문", "외대앞", "회기", "청량리|청량리(서울시립대입구)", "제기동", "신설동", "동묘앞", "동대문", "종로5가", "종로3가", "종각", "시청", "서울역||서울", "남영", "용산", "노량진", "대방", "신길", "영등포", "신도림", "구로", "구일", "개봉", "오류동", "온수|온수(성공회대입구)", "역곡", "소사", "부천", "중동", "송내", "부개", "부평", "백운", "동암", "간석", "주안", "도화", "제물포", "도원", "동인천", "인천"
            ]),
            PatternSeed("sinchang", "연천 → 신창", [
                "연천", "전곡", "청산", "소요산", "동두천", "보산", "동두천중앙", "지행", "덕정", "덕계", "양주", "녹양", "가능", "의정부", "회룡", "망월사", "도봉산", "도봉", "방학", "창동", "녹천", "월계", "광운대", "석계", "신이문", "외대앞", "회기", "청량리|청량리(서울시립대입구)", "제기동", "신설동", "동묘앞", "동대문", "종로5가", "종로3가", "종각", "시청", "서울역||서울", "남영", "용산", "노량진", "대방", "신길", "영등포", "신도림", "구로", "가산디지털단지", "독산", "금천구청", "석수", "관악", "안양", "명학", "금정", "군포", "당정", "의왕", "성균관대", "화서", "수원", "세류", "병점", "세마", "오산대", "오산", "진위", "송탄", "서정리", "평택지제", "평택", "성환", "직산", "두정", "천안", "봉명", "쌍용|쌍용(나사렛대)", "아산", "탕정", "배방", "온양온천", "신창|신창(순천향대)"
            ]),
            PatternSeed("gwangmyeong", "영등포 → 광명", kind: "branch", [
                "영등포", "신도림", "구로", "가산디지털단지", "독산", "금천구청", "광명"
            ]),
            PatternSeed("seodongtan", "병점 → 서동탄", kind: "branch", ["병점", "서동탄"])
        ]
    ),
    LineSeed(
        line: Line(id: "seoul-2", regionID: "capital", operatorID: "seoul-metro", name: "서울 2호선", shortName: "2", colorHex: "00A84D", sortOrder: 2),
        prefix: "s2",
        patterns: [
            PatternSeed("loop", "순환선", kind: "loop", [
                "시청", "을지로입구", "을지로3가", "을지로4가", "동대문역사문화공원|동대문역사문화공원(DDP)", "신당", "상왕십리", "왕십리|왕십리(성동구청)", "한양대", "뚝섬", "성수", "건대입구", "구의|구의(광진구청)", "강변|강변(동서울터미널)", "잠실나루", "잠실|잠실(송파구청)", "잠실새내", "종합운동장", "삼성|삼성(무역센터)", "선릉", "역삼", "강남", "교대|교대(법원·검찰청)", "서초", "방배", "사당", "낙성대|낙성대(강감찬)", "서울대입구|서울대입구(관악구청)", "봉천", "신림", "신대방", "구로디지털단지|구로디지털단지(원광디지털대)", "대림|대림(구로구청)", "신도림", "문래", "영등포구청", "당산", "합정", "홍대입구", "신촌", "이대", "아현", "충정로|충정로(경기대입구)", "시청"
            ]),
            PatternSeed("seongsu", "성수 → 신설동", kind: "branch", ["성수", "용답", "신답", "용두|용두(동대문구청)", "신설동"]),
            PatternSeed("sinjeong", "신도림 → 까치산", kind: "branch", ["신도림", "도림천", "양천구청", "신정네거리", "까치산"])
        ]
    ),
    LineSeed(
        line: Line(id: "seoul-3", regionID: "capital", operatorID: "seoul-metro", name: "서울 3호선", shortName: "3", colorHex: "EF7C1C", sortOrder: 3),
        prefix: "s3",
        patterns: [
            PatternSeed("지축 → 오금", [
                "지축", "구파발", "연신내", "불광", "녹번", "홍제", "무악재", "독립문", "경복궁|경복궁(정부서울청사)", "안국", "종로3가", "을지로3가", "충무로", "동대입구", "약수", "금호", "옥수", "압구정", "신사", "잠원", "고속터미널", "교대|교대(법원·검찰청)", "남부터미널|남부터미널(예술의전당)", "양재|양재(서초구청)", "매봉", "도곡", "대치", "학여울|학여울(서울무역전시컨벤션센터)", "대청", "일원", "수서", "가락시장", "경찰병원", "오금"
            ]),
            PatternSeed("full", "대화 → 오금", [
                "대화", "주엽", "정발산", "마두", "백석", "대곡", "화정", "원당", "원흥", "삼송", "지축", "구파발", "연신내", "불광", "녹번", "홍제", "무악재", "독립문", "경복궁|경복궁(정부서울청사)", "안국", "종로3가", "을지로3가", "충무로", "동대입구", "약수", "금호", "옥수", "압구정", "신사", "잠원", "고속터미널", "교대|교대(법원·검찰청)", "남부터미널|남부터미널(예술의전당)", "양재|양재(서초구청)", "매봉", "도곡", "대치", "학여울|학여울(서울무역전시컨벤션센터)", "대청", "일원", "수서", "가락시장", "경찰병원", "오금"
            ])
        ]
    ),
    LineSeed(
        line: Line(id: "seoul-4", regionID: "capital", operatorID: "seoul-metro", name: "서울 4호선", shortName: "4", colorHex: "00A5DE", sortOrder: 4),
        prefix: "s4",
        patterns: [
            PatternSeed("진접 → 남태령", [
                "진접|진접(경복대)", "오남", "별내별가람", "당고개", "상계", "노원", "창동", "쌍문", "수유|수유(강북구청)", "미아|미아(서울사이버대학)", "미아사거리", "길음", "성신여대입구|성신여대입구(돈암)", "한성대입구|한성대입구(삼선교)", "혜화", "동대문", "동대문역사문화공원|동대문역사문화공원(DDP)", "충무로", "명동", "회현|회현(남대문시장)", "서울역||서울", "숙대입구|숙대입구(갈월)", "삼각지", "신용산", "이촌|이촌(국립중앙박물관)", "동작|동작(현충원)", "총신대입구|총신대입구(이수)", "사당", "남태령"
            ]),
            PatternSeed("full", "진접 → 오이도", [
                "진접|진접(경복대)", "오남", "별내별가람", "당고개", "상계", "노원", "창동", "쌍문", "수유|수유(강북구청)", "미아|미아(서울사이버대학)", "미아사거리", "길음", "성신여대입구|성신여대입구(돈암)", "한성대입구|한성대입구(삼선교)", "혜화", "동대문", "동대문역사문화공원|동대문역사문화공원(DDP)", "충무로", "명동", "회현|회현(남대문시장)", "서울역||서울", "숙대입구|숙대입구(갈월)", "삼각지", "신용산", "이촌|이촌(국립중앙박물관)", "동작|동작(현충원)", "총신대입구|총신대입구(이수)", "사당", "남태령", "선바위", "경마공원", "대공원", "과천", "정부과천청사", "인덕원", "평촌", "범계", "금정", "산본", "수리산", "대야미", "반월", "상록수", "한대앞", "중앙", "고잔", "초지", "안산", "신길온천", "정왕", "오이도"
            ])
        ]
    ),
    LineSeed(
        line: Line(id: "seoul-5", regionID: "capital", operatorID: "seoul-metro", name: "서울 5호선", shortName: "5", colorHex: "996CAC", sortOrder: 5),
        prefix: "s5",
        patterns: [
            PatternSeed("hanam", "방화 → 하남검단산", [
                "방화", "개화산", "김포공항", "송정", "마곡", "발산", "우장산", "화곡", "까치산", "신정|신정(은행정)", "목동", "오목교|오목교(목동운동장앞)", "양평", "영등포구청", "영등포시장", "신길", "여의도", "여의나루", "마포", "공덕", "애오개", "충정로|충정로(경기대입구)", "서대문", "광화문|광화문(세종문화회관)", "종로3가", "을지로4가", "동대문역사문화공원|동대문역사문화공원(DDP)", "청구", "신금호", "행당", "왕십리|왕십리(성동구청)", "마장", "답십리", "장한평", "군자|군자(능동)", "아차산|아차산(어린이대공원후문)", "광나루|광나루(장신대)", "천호|천호(풍납토성)", "강동", "길동", "굽은다리|굽은다리(강동구민회관앞)", "명일", "고덕", "상일동", "강일", "미사", "하남풍산", "하남시청|하남시청(덕풍·신장)", "하남검단산"
            ]),
            PatternSeed("macheon", "방화 → 마천", kind: "branch", [
                "방화", "개화산", "김포공항", "송정", "마곡", "발산", "우장산", "화곡", "까치산", "신정|신정(은행정)", "목동", "오목교|오목교(목동운동장앞)", "양평", "영등포구청", "영등포시장", "신길", "여의도", "여의나루", "마포", "공덕", "애오개", "충정로|충정로(경기대입구)", "서대문", "광화문|광화문(세종문화회관)", "종로3가", "을지로4가", "동대문역사문화공원|동대문역사문화공원(DDP)", "청구", "신금호", "행당", "왕십리|왕십리(성동구청)", "마장", "답십리", "장한평", "군자|군자(능동)", "아차산|아차산(어린이대공원후문)", "광나루|광나루(장신대)", "천호|천호(풍납토성)", "강동", "둔촌동", "올림픽공원|올림픽공원(한국체대)", "방이", "오금", "개롱", "거여", "마천"
            ])
        ]
    ),
    LineSeed(
        line: Line(id: "seoul-6", regionID: "capital", operatorID: "seoul-metro", name: "서울 6호선", shortName: "6", colorHex: "CD7C2F", sortOrder: 6),
        prefix: "s6",
        patterns: [PatternSeed("loop", "응암순환 → 신내", kind: "loop", [
            "응암", "역촌", "불광", "독바위", "연신내", "구산", "응암", "새절|새절(신사)", "증산|증산(명지대앞)", "디지털미디어시티", "월드컵경기장|월드컵경기장(성산)", "마포구청", "망원", "합정", "상수", "광흥창|광흥창(서강)", "대흥|대흥(서강대앞)", "공덕", "효창공원앞", "삼각지", "녹사평|녹사평(용산구청)", "이태원", "한강진", "버티고개", "약수", "청구", "신당", "동묘앞", "창신", "보문", "안암|안암(고대병원앞)", "고려대|고려대(종암)", "월곡|월곡(동덕여대)", "상월곡|상월곡(한국과학기술연구원)", "돌곶이", "석계", "태릉입구", "화랑대|화랑대(서울여대입구)", "봉화산|봉화산(서울의료원)", "신내"
        ])]
    ),
    LineSeed(
        line: Line(id: "seoul-7", regionID: "capital", operatorID: "seoul-metro", name: "서울 7호선", shortName: "7", colorHex: "747F00", sortOrder: 7),
        prefix: "s7",
        patterns: [PatternSeed("장암 → 석남", [
            "장암", "도봉산", "수락산", "마들", "노원", "중계", "하계", "공릉|공릉(서울과학기술대)", "태릉입구", "먹골", "중화", "상봉|상봉(시외버스터미널)", "면목", "사가정", "용마산|용마산(용마폭포공원)", "중곡", "군자|군자(능동)", "어린이대공원|어린이대공원(세종대)", "건대입구", "뚝섬유원지", "청담|청담(한국금거래소)", "강남구청", "학동", "논현", "반포", "고속터미널", "내방", "총신대입구|총신대입구(이수)", "남성", "숭실대입구|숭실대입구(살피재)", "상도", "장승배기", "신대방삼거리", "보라매", "신풍", "대림|대림(구로구청)", "남구로", "가산디지털단지", "철산", "광명사거리", "천왕", "온수|온수(성공회대입구)", "까치울", "부천종합운동장", "춘의", "신중동", "부천시청", "상동", "삼산체육관", "굴포천", "부평구청", "산곡", "석남"
        ])]
    ),
    LineSeed(
        line: Line(id: "seoul-8", regionID: "capital", operatorID: "seoul-metro", name: "서울 8호선", shortName: "8", colorHex: "E6186C", sortOrder: 8),
        prefix: "s8",
        patterns: [PatternSeed("별내 → 모란", [
            "별내", "다산", "동구릉", "구리", "장자호수공원", "암사역사공원", "암사", "천호|천호(풍납토성)", "강동구청", "몽촌토성|몽촌토성(평화의문)", "잠실|잠실(송파구청)", "석촌", "송파", "가락시장", "문정", "장지", "복정", "남위례", "산성", "남한산성입구|남한산성입구(성남법원·검찰청)", "단대오거리", "신흥", "수진", "모란"
        ])]
    ),
    LineSeed(
        line: Line(id: "seoul-9", regionID: "capital", operatorID: "metro9", name: "서울 9호선", shortName: "9", colorHex: "BDB092", sortOrder: 9),
        prefix: "s9",
        patterns: [PatternSeed("개화 → 중앙보훈병원", [
            "개화", "김포공항", "공항시장", "신방화", "마곡나루|마곡나루(서울식물원)", "양천향교", "가양", "증미", "등촌", "염창", "신목동", "선유도", "당산", "국회의사당", "여의도", "샛강", "노량진", "노들", "흑석|흑석(중앙대입구)", "동작|동작(현충원)", "구반포", "신반포", "고속터미널", "사평", "신논현", "언주", "선정릉", "삼성중앙", "봉은사", "종합운동장", "삼전", "석촌고분", "석촌", "송파나루", "한성백제", "올림픽공원|올림픽공원(한국체대)", "둔촌오륜", "중앙보훈병원"
        ])]
    ),
    LineSeed(
        line: Line(id: "seoul-ui", regionID: "capital", operatorID: "ui-line", name: "우이신설선", shortName: "UI", colorHex: "B7C452", sortOrder: 10),
        prefix: "sui",
        patterns: [PatternSeed("북한산우이 → 신설동", [
            "북한산우이|북한산우이(도선사입구)", "솔밭공원", "4·19민주묘지", "가오리", "화계", "삼양", "삼양사거리", "솔샘", "북한산보국문|북한산보국문(서경대)", "정릉|정릉(국민대입구)", "성신여대입구|성신여대입구(돈암)", "보문", "신설동"
        ])]
    ),
    LineSeed(
        line: Line(id: "seoul-sillim", regionID: "capital", operatorID: "sillim-line", name: "신림선", shortName: "SL", colorHex: "6789CA", sortOrder: 11),
        prefix: "ssl",
        patterns: [PatternSeed("샛강 → 관악산", [
            "샛강", "대방|대방(성애병원)", "서울지방병무청", "보라매", "보라매공원", "보라매병원|보라매병원(전문건설회관)", "당곡", "신림", "서원", "서울대벤처타운", "관악산|관악산(서울대)"
        ])]
    ),
    LineSeed(
        line: Line(id: "incheon-1", regionID: "capital", operatorID: "incheon-transit", name: "인천 1호선", shortName: "I1", colorHex: "7CA8D5", sortOrder: 12),
        prefix: "i1",
        patterns: [PatternSeed("검단호수공원 → 송도달빛축제공원", [
            "검단호수공원", "신검단중앙", "아라", "계양", "귤현", "박촌", "임학", "계산", "경인교대입구", "작전", "갈산", "부평구청", "부평시장", "부평", "동수", "부평삼거리", "간석오거리", "인천시청", "예술회관", "인천터미널", "문학경기장", "선학", "신연수", "원인재", "동춘", "동막", "캠퍼스타운", "테크노파크", "지식정보단지", "인천대입구", "센트럴파크", "국제업무지구", "송도달빛축제공원"
        ])]
    ),
    LineSeed(
        line: Line(id: "incheon-2", regionID: "capital", operatorID: "incheon-transit", name: "인천 2호선", shortName: "I2", colorHex: "E6B64A", sortOrder: 13),
        prefix: "i2",
        patterns: [PatternSeed("검단오류 → 운연", [
            "검단오류|검단오류(검단산업단지)", "왕길", "검단사거리", "마전", "완정", "독정", "검암", "검바위", "아시아드경기장|아시아드경기장(공촌사거리)", "서구청", "가정|가정(루원시티)", "가정중앙시장", "석남|석남(거북시장)", "서부여성회관", "인천가좌", "가재울", "주안국가산단", "주안", "시민공원|시민공원(문화창작지대)", "석바위시장", "인천시청", "석천사거리", "모래내시장", "만수", "남동구청", "인천대공원", "운연|운연(서창)"
        ])]
    ),
    LineSeed(
        line: Line(id: "suin-bundang", regionID: "capital", operatorID: "korail", name: "수인분당선", shortName: "수인", colorHex: "F5A200", sortOrder: 14),
        prefix: "sb",
        patterns: [PatternSeed("청량리 → 인천", [
            "청량리|청량리(서울시립대입구)", "왕십리|왕십리(성동구청)", "서울숲", "압구정로데오", "강남구청", "선정릉", "선릉", "한티", "도곡", "구룡", "개포동", "대모산입구", "수서", "복정", "가천대", "태평", "모란", "야탑", "이매", "서현", "수내|수내(한국잡월드)", "정자", "미금|미금(분당서울대병원)", "오리", "죽전|죽전(단국대)", "보정", "구성", "신갈", "기흥|기흥(백남준아트센터)", "상갈|상갈(루터대학교)", "청명", "영통|영통(경희대)", "망포", "매탄권선", "수원시청|수원시청(경기아트센터)", "매교", "수원", "고색", "오목천|오목천(수원여대)", "어천", "야목", "사리", "한대앞", "중앙", "고잔", "초지", "안산", "능길", "정왕", "오이도", "달월", "월곶", "소래포구", "인천논현", "호구포", "남동인더스파크", "원인재", "연수", "송도", "인하대", "숭의|숭의(인하대병원)", "신포", "인천"
        ])]
    ),
    LineSeed(
        line: Line(id: "gyeongui-jungang", regionID: "capital", operatorID: "korail", name: "경의중앙선", shortName: "경의", colorHex: "77C4A3", sortOrder: 15),
        prefix: "gj",
        patterns: [
            PatternSeed("jipyeong", "문산 → 지평", [
                "문산", "파주", "월롱", "금촌", "금릉", "운정", "야당", "탄현", "일산", "풍산", "백마", "곡산", "대곡", "능곡", "행신", "강매", "한국항공대", "수색", "디지털미디어시티", "가좌", "홍대입구", "서강대", "공덕", "효창공원앞", "용산", "이촌|이촌(국립중앙박물관)", "서빙고", "한남", "옥수", "응봉", "왕십리|왕십리(성동구청)", "청량리|청량리(서울시립대입구)", "회기", "중랑", "상봉|상봉(시외버스터미널)", "망우", "양원", "구리", "도농", "양정", "덕소", "도심", "팔당", "운길산", "양수", "신원", "국수", "아신", "오빈", "양평", "원덕", "용문", "지평"
            ]),
            PatternSeed("seoul", "문산 → 서울역", kind: "branch", [
                "문산", "파주", "월롱", "금촌", "금릉", "운정", "야당", "탄현", "일산", "풍산", "백마", "곡산", "대곡", "능곡", "행신", "강매", "한국항공대", "수색", "디지털미디어시티", "가좌", "신촌|신촌(경의선)", "서울역||서울"
            ]),
            PatternSeed("dorasan", "문산 → 도라산", kind: "branch", [
                "문산", "운천", "임진강", "도라산"
            ])
        ]
    ),
    LineSeed(
        line: Line(id: "gyeongchun", regionID: "capital", operatorID: "korail", name: "경춘선", shortName: "경춘", colorHex: "0C8E72", sortOrder: 16),
        prefix: "gc",
        patterns: [PatternSeed("청량리 → 춘천", [
            "청량리|청량리(서울시립대입구)", "회기", "중랑", "상봉|상봉(시외버스터미널)", "망우", "신내", "갈매", "별내", "퇴계원", "사릉", "금곡", "평내호평", "천마산", "마석", "대성리", "청평", "상천", "가평", "굴봉산", "백양리", "강촌", "김유정", "남춘천", "춘천"
        ])]
    ),
    LineSeed(
        line: Line(id: "gyeonggang", regionID: "capital", operatorID: "korail", name: "경강선", shortName: "경강", colorHex: "003DA5", sortOrder: 17),
        prefix: "gg",
        patterns: [PatternSeed("판교 → 여주", [
            "판교|판교(판교테크노밸리)", "성남", "이매", "삼동", "경기광주", "초월", "곤지암", "신둔도예촌", "이천", "부발", "세종대왕릉", "여주"
        ])]
    ),
    LineSeed(
        line: Line(id: "seohae", regionID: "capital", operatorID: "korail", name: "서해선", shortName: "서해", colorHex: "8FC31F", sortOrder: 18),
        prefix: "sh",
        patterns: [PatternSeed("일산 → 원시", [
            "일산", "풍산", "백마", "곡산", "대곡", "능곡", "김포공항", "원종", "부천종합운동장", "소사", "소새울", "시흥대야", "신천", "신현", "시흥시청", "시흥능곡", "달미", "선부", "초지", "시우", "원시"
        ])]
    ),
    LineSeed(
        line: Line(id: "shinbundang", regionID: "capital", operatorID: "shinbundang", name: "신분당선", shortName: "신분", colorHex: "D4003B", sortOrder: 19),
        prefix: "dx",
        patterns: [PatternSeed("신사 → 광교", [
            "신사", "논현", "신논현", "강남", "양재|양재(서초구청)", "양재시민의숲|양재시민의숲(매헌)", "청계산입구", "판교|판교(판교테크노밸리)", "정자", "미금|미금(분당서울대병원)", "동천", "수지구청", "성복", "상현", "광교중앙|광교중앙(아주대)", "광교|광교(경기대)"
        ])]
    ),
    LineSeed(
        line: Line(id: "arex", regionID: "capital", operatorID: "arex", name: "공항철도", shortName: "AREX", colorHex: "0090D2", sortOrder: 20),
        prefix: "ar",
        patterns: [PatternSeed("서울역 → 인천공항2터미널", [
            "서울역||서울", "공덕", "홍대입구", "디지털미디어시티", "마곡나루|마곡나루(서울식물원)", "김포공항", "계양", "검암", "청라국제도시", "영종", "운서", "공항화물청사", "인천공항1터미널", "인천공항2터미널"
        ])]
    ),
    LineSeed(
        line: Line(id: "busan-1", regionID: "busan", operatorID: "busan-transit", name: "부산 1호선", shortName: "1", colorHex: "F06A00", sortOrder: 1),
        prefix: "b1",
        patterns: [PatternSeed("다대포해수욕장 → 노포", [
            "다대포해수욕장", "다대포항", "낫개", "신장림", "장림", "동매", "신평", "하단", "당리|당리(사하구청)", "사하", "괴정", "대티|대티(동주대학)", "서대신", "동대신", "토성", "자갈치", "남포", "중앙", "부산역", "초량", "부산진", "좌천", "범일", "범내골", "서면", "부전|부전(부산시민공원·송상현광장)", "양정", "시청|시청(연제)", "연산", "교대", "동래", "명륜", "온천장", "부산대", "장전", "구서", "두실", "남산", "범어사", "노포|노포(종합버스터미널)"
        ])]
    ),
    LineSeed(
        line: Line(id: "busan-2", regionID: "busan", operatorID: "busan-transit", name: "부산 2호선", shortName: "2", colorHex: "81BF48", sortOrder: 2),
        prefix: "b2",
        patterns: [PatternSeed("장산 → 양산", [
            "장산", "중동", "해운대", "동백", "벡스코|벡스코(시립미술관)", "센텀시티|센텀시티(벡스코)", "민락", "수영", "광안", "금련산", "남천|남천(KBS·수영구청)", "경성대·부경대", "대연", "못골|못골(남구청)", "지게골", "문현", "국제금융센터·부산은행", "전포", "서면", "부암", "가야", "동의대", "개금", "냉정", "주례", "감전", "사상", "덕포", "모라", "모덕", "구포", "구명", "덕천", "수정", "화명", "율리", "동원", "금곡", "호포", "증산", "부산대양산캠퍼스", "남양산|남양산(범어)", "양산|양산(시청)"
        ])]
    ),
    LineSeed(
        line: Line(id: "busan-3", regionID: "busan", operatorID: "busan-transit", name: "부산 3호선", shortName: "3", colorHex: "BB8C00", sortOrder: 3),
        prefix: "b3",
        patterns: [PatternSeed("수영 → 대저", [
            "수영", "망미|망미(병무청)", "배산", "물만골", "연산", "거제|거제(법원·검찰청)", "종합운동장|종합운동장(빅토리움)", "사직", "미남", "만덕", "남산정|남산정(부산폴리텍대학)", "숙등|숙등(부민병원)", "덕천", "구포", "강서구청", "체육공원", "대저"
        ])]
    ),
    LineSeed(
        line: Line(id: "busan-4", regionID: "busan", operatorID: "busan-transit", name: "부산 4호선", shortName: "4", colorHex: "2E67A4", sortOrder: 4),
        prefix: "b4",
        patterns: [PatternSeed("미남 → 안평", [
            "미남", "동래", "수안|수안(동래읍성임진왜란역사관)", "낙민", "충렬사|충렬사(안락)", "명장", "서동", "금사", "반여농산물시장", "석대", "영산대|영산대(아랫반송)", "동부산대학|동부산대학(윗반송)", "고촌", "안평|안평(고촌주택단지)"
        ])]
    ),
    LineSeed(
        line: Line(id: "busan-gimhae", regionID: "busan", operatorID: "bgl", name: "부산김해경전철", shortName: "BGL", colorHex: "875CAC", sortOrder: 5),
        prefix: "bgl",
        patterns: [PatternSeed("사상 → 가야대", [
            "사상|사상(서부터미널)", "괘법르네시떼|괘법르네시떼(강변공원)", "서부산유통지구|서부산유통지구(금호마을·에어부산)", "공항", "덕두", "등구", "대저", "평강", "대사", "불암", "지내", "김해대학|김해대학(안동)", "인제대|인제대(활천)", "김해시청", "부원|부원(아이스퀘어몰)", "봉황|봉황(김해여객터미널)", "수로왕릉|수로왕릉(김해보건소)", "박물관", "연지공원", "장신대|장신대(화정)", "가야대|가야대(삼계)"
        ])]
    ),
    LineSeed(
        line: Line(id: "donghae", regionID: "busan", operatorID: "korail", name: "동해선", shortName: "동해", colorHex: "0054A6", sortOrder: 6),
        prefix: "dh",
        patterns: [PatternSeed("부전 → 태화강", [
            "부전", "거제해맞이", "거제", "교대", "동래", "안락", "부산원동", "재송", "센텀", "벡스코", "신해운대", "송정", "오시리아", "기장", "일광", "좌천", "월내", "서생", "남창", "망양", "덕하", "개운포", "태화강"
        ])]
    ),
    LineSeed(
        line: Line(id: "daegu-1", regionID: "daegu", operatorID: "daegu-transit", name: "대구 1호선", shortName: "1", colorHex: "D93F5C", sortOrder: 1),
        prefix: "d1",
        patterns: [PatternSeed("설화명곡 → 하양", [
            "설화명곡", "화원", "대곡|대곡(정부대구청사)", "진천", "월배", "상인", "월촌", "송현", "서부정류장|서부정류장(관문시장)", "대명", "안지랑", "현충로", "영대병원", "교대", "명덕|명덕(2·28민주운동기념회관)", "반월당", "중앙로", "대구역", "칠성시장", "신천|신천(경북대입구)", "동대구역", "동구청|동구청(큰고개)", "아양교|아양교(대구국제공항입구)", "동촌|동촌(동촌유원지)", "해안", "방촌", "용계", "율하", "신기", "반야월", "각산", "안심|안심(혁신도시·첨복단지)", "대구한의대병원", "부호|부호(경일대·호산대)", "하양|하양(대구가톨릭대)"
        ])]
    ),
    LineSeed(
        line: Line(id: "daegu-2", regionID: "daegu", operatorID: "daegu-transit", name: "대구 2호선", shortName: "2", colorHex: "00AA80", sortOrder: 2),
        prefix: "d2",
        patterns: [PatternSeed("문양 → 영남대", [
            "문양", "다사", "대실", "강창", "계명대", "성서산업단지", "이곡", "용산|용산(서부법원·검찰청입구)", "죽전", "감삼", "두류", "내당", "반고개", "청라언덕|청라언덕(신남)", "반월당", "경대병원", "대구은행|대구은행(대구교육청)", "범어", "수성구청|수성구청(KBS)", "만촌", "담티|담티(수성대·대륜)", "연호", "대공원|대공원(삼성라이온즈파크)", "고산", "신매", "사월", "정평", "임당", "영남대"
        ])]
    ),
    LineSeed(
        line: Line(id: "daegu-3", regionID: "daegu", operatorID: "daegu-transit", name: "대구 3호선", shortName: "3", colorHex: "FDB913", sortOrder: 3),
        prefix: "d3",
        patterns: [PatternSeed("칠곡경대병원 → 용지", [
            "칠곡경대병원", "학정", "팔거|팔거(국립농관원·통계청)", "동천", "칠곡운암", "구암", "태전", "매천", "매천시장", "팔달", "공단", "만평", "팔달시장", "원대", "북구청", "달성공원", "서문시장|서문시장(동산병원)", "청라언덕|청라언덕(신남)", "남산|남산(계명네거리)", "명덕|명덕(2·28민주운동기념회관)", "건들바위", "대봉교", "수성시장", "수성구민운동장", "어린이세상", "황금", "수성못|수성못(TBC)", "지산", "범물", "용지"
        ])]
    ),
    LineSeed(
        line: Line(id: "daegyeong", regionID: "daegu", operatorID: "korail", name: "대경선", shortName: "대경", colorHex: "0054A6", sortOrder: 4),
        prefix: "dk",
        patterns: [PatternSeed("구미 → 경산", [
            "구미", "사곡", "왜관", "서대구", "대구", "동대구", "경산"
        ])]
    ),
    LineSeed(
        line: Line(id: "gwangju-1", regionID: "gwangju", operatorID: "gwangju-transit", name: "광주 1호선", shortName: "1", colorHex: "009088", sortOrder: 1),
        prefix: "g1",
        patterns: [PatternSeed("녹동 → 평동", [
            "녹동", "소태", "학동·증심사입구", "남광주", "문화전당|문화전당(구도청)", "금남로4가", "금남로5가", "양동시장", "돌고개", "농성", "화정", "쌍촌", "운천", "상무", "김대중컨벤션센터|김대중컨벤션센터(마륵)", "공항", "송정공원", "광주송정", "도산", "평동"
        ])]
    ),
    LineSeed(
        line: Line(id: "daejeon-1", regionID: "daejeon", operatorID: "daejeon-transit", name: "대전 1호선", shortName: "1", colorHex: "007448", sortOrder: 1),
        prefix: "dj1",
        patterns: [PatternSeed("판암 → 반석", [
            "판암|판암(대전대)", "신흥", "대동|대동(우송대)", "대전역", "중앙로", "중구청", "서대전네거리", "오룡", "용문", "탄방", "시청", "정부청사", "갈마", "월평|월평(한국과학기술원)", "갑천", "유성온천|유성온천(충남대·목원대)", "구암", "현충원|현충원(한밭대)", "월드컵경기장|월드컵경기장(노은도매시장)", "노은", "지족|지족(침신대)", "반석|반석(칠성대)"
        ])]
    )
]

var stations: [Station] = []
var patterns: [Pattern] = []

for seed in lineSeeds {
    var stationIDByName: [String: String] = [:]
    for patternSeed in seed.patterns {
        let ids = patternSeed.stations.map { raw -> String in
            let baseName = raw.split(separator: "|", omittingEmptySubsequences: false).first.map(String.init) ?? raw
            if let id = stationIDByName[baseName] { return id }
            let id = "\(seed.prefix)-\(String(format: "%03d", stationIDByName.count + 1))"
            stationIDByName[baseName] = id
            stations.append(decodeStation(raw, id: id))
            return id
        }
        patterns.append(Pattern(
            id: "\(seed.line.id)-\(patternSeed.suffix)",
            lineID: seed.line.id,
            name: patternSeed.name,
            kind: patternSeed.kind,
            stationIDs: ids
        ))
    }
}

let catalog = Catalog(
    schemaVersion: 1,
    contentVersion: "2026.08.official.3",
    challengePoolVersion: "2026.08.3",
    dataAsOf: "2026-08-22",
    sources: [
        Source(title: "국가철도공단 전국도시철도역사정보 표준데이터", url: URL(string: "https://www.data.go.kr/data/15013205/standard.do")!),
        Source(title: "서울교통공사 사이버스테이션", url: URL(string: "https://www.seoulmetro.co.kr/kr/cyberStation.do?menuIdx=538")!),
        Source(title: "서울시메트로9호선", url: URL(string: "https://www.metro9.co.kr/")!),
        Source(title: "우이신설도시철도", url: URL(string: "https://www.ui-line.com/")!),
        Source(title: "신림선도시철도", url: URL(string: "https://www.sillimlrt.com/")!),
        Source(title: "인천교통공사 노선도 및 역정보", url: URL(string: "https://www.ictr.or.kr/main/railway/guidance/map.jsp")!),
        Source(title: "한국철도공사 광역철도 운영노선", url: URL(string: "https://info.korail.com/info/contents.do?key=1446")!),
        Source(title: "국가철도공단 수도권1호선 역정보", url: URL(string: "https://www.data.go.kr/data/15041013/fileData.do")!),
        Source(title: "신분당선 노선도", url: URL(string: "https://www.shinbundang.co.kr/dxline/dxline1.jsp")!),
        Source(title: "공항철도 역·운임 정보", url: URL(string: "https://www.arex.or.kr/content.do?menuNo=MN201503060000000002")!),
        Source(title: "부산교통공사 노선도", url: URL(string: "https://www2.humetro.busan.kr/homepage/default/page/subLocation.do?menu_no=10010101")!),
        Source(title: "부산김해경전철 노선도", url: URL(string: "https://www.bglrt.com/00162.web")!),
        Source(title: "대구교통공사", url: URL(string: "https://www.dtro.or.kr/")!),
        Source(title: "광주교통공사 사이버스테이션", url: URL(string: "https://www.grtc.co.kr/cyber/map")!),
        Source(title: "대전교통공사 노선도", url: URL(string: "https://www.djtc.kr/kor/board.do?bbsIdx=4567&menuIdx=325")!)
    ],
    regions: regions,
    operators: operators,
    stations: stations,
    lines: lineSeeds.map(\.line),
    routePatterns: patterns
)

let output = CommandLine.arguments.dropFirst().first ?? "RememberSubway/Resources/transit_data.json"
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
let data = try encoder.encode(catalog)
try data.write(to: URL(fileURLWithPath: output), options: .atomic)
print("Wrote \(catalog.lines.count)개 노선, \(catalog.stations.count)개 역, \(catalog.routePatterns.count)개 계통 → \(output)")
