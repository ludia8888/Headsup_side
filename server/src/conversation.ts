import { randomInt } from "node:crypto";

export interface ConversationPlan {
  id: string;
  kind: string;
  brief: string;
  opening: string;
}

// These are creative starting points, not a bank of recordings or a full script.
// The model adapts each conversation to the chosen persona and the user's answer.
export const conversationIdeas: readonly ConversationPlan[] = [
  { id: "dragon-roommate", kind: "상상", brief: "손바닥만 한 용과 함께 산다면 생길 일을 함께 상상한다.",
    opening: "우리 집에 손바닥만 한 용이 들어오면, 이름부터 지을까 숨길 곳부터 찾을까?" },
  { id: "cat-for-mayor", kind: "상상", brief: "고양이가 동네 시장이 된 세계의 첫 정책을 함께 만든다.",
    opening: "동네 시장이 고양이가 됐대. 첫 번째 공약이 뭘 것 같아?" },
  { id: "moon-picnic", kind: "상상", brief: "달에서 소풍을 한다는 가상의 상황에서 엉뚱한 준비물을 고른다.",
    opening: "달에 소풍 가면 김밥 말고 뭘 챙겨야 할까?" },
  { id: "tiny-superpower", kind: "선택 놀이", brief: "쓸모가 작고 귀여운 초능력 두 가지 중 하나를 고르고 이유를 듣는다.",
    opening: "과자 봉지 조용히 뜯기랑 이불에서 완벽한 온도 찾기, 초능력 하나만 고르면 뭐야?" },
  { id: "rain-soundtrack", kind: "선택 놀이", brief: "비 오는 날 어울리는 분위기를 선택하게 하고 취향을 이야기한다.",
    opening: "비 오는 날 배경음악은 재즈야, 아니면 영화 주인공처럼 웅장한 음악이야?" },
  { id: "one-silly-rule", kind: "선택 놀이", brief: "하루 동안 세계에 적용할 무해하고 엉뚱한 규칙을 함께 고른다.",
    opening: "내일 하루 모든 엘리베이터가 인사한다면, 무슨 말을 해야 덜 어색할까?" },
  { id: "cloud-complaint", kind: "미니 상황극", brief: "가상의 구름 고객센터로 시작하되 실제 상황이라고 속이지 않는다.",
    opening: "지금부터 구름 고객센터야. 오늘 하늘에 어떤 요청 넣어줄까?" },
  { id: "bread-interview", kind: "미니 상황극", brief: "빵집에 취직하려는 가상의 크루아상을 면접하는 역할 놀이를 한다.",
    opening: "크루아상 면접관이 됐다고 상상해 봐. 첫 질문 뭘로 할까?" },
  { id: "alien-tour-guide", kind: "미니 상황극", brief: "처음 지구에 온 외계인에게 평범한 물건 하나를 설명하는 놀이를 한다.",
    opening: "내가 처음 지구에 온 외계인 역할 할게. 베개가 왜 필요한지 설명해 줄래?" },
  { id: "penguin-ending", kind: "짧은 이야기", brief: "가상 펭귄이 카페를 차리는 짧은 이야기의 다음 장면을 함께 만든다.",
    opening: "상상 속 펭귄이 카페를 열었는데 첫 메뉴가 따뜻한 얼음이래. 다음 메뉴는 뭘까?" },
  { id: "lost-moon-sock", kind: "짧은 이야기", brief: "달이 양말 한 짝을 잃어버린 동화 같은 설정의 결말을 함께 만든다.",
    opening: "달이 양말 한 짝을 잃어버렸다는 이야기를 만들고 있어. 누가 가져갔을까?" },
  { id: "umbrella-holiday", kind: "짧은 이야기", brief: "가상 우산이 휴가를 간 이야기에서 예상 밖의 행선지를 만든다.",
    opening: "우산이 휴가를 간다면 비 오는 나라를 갈까, 햇빛 쨍한 나라를 갈까?" },
  { id: "weekday-flavor", kind: "취향 발견", brief: "요일을 맛에 비유하는 가벼운 취향 대화를 한다.",
    opening: "오늘을 아이스크림 맛으로 표현하면 무슨 맛이야?" },
  { id: "sound-of-cozy", kind: "취향 발견", brief: "편안한 느낌을 주는 소리를 묻고 사용자의 느낌에 공감한다.",
    opening: "편안한 소리 하나만 고르면 빗소리야, 보글보글 끓는 소리야?" },
  { id: "room-title", kind: "취향 발견", brief: "지금 떠오르는 공간에 영화 제목을 붙이는 가벼운 대화를 한다. 현재 공간을 봤다고 말하지 않는다.",
    opening: "네 방에 영화 제목을 붙인다면 뭐라고 하고 싶어?" },
  { id: "sandwich-debate", kind: "엉뚱한 토론", brief: "샌드위치의 가장자리 같은 사소한 소재를 장난스럽게 토론한다.",
    opening: "샌드위치 모서리가 제일 맛있다는 주장, 어떻게 생각해?" },
  { id: "socks-personality", kind: "엉뚱한 토론", brief: "양말에 성격이 있다면 어떨지 가볍게 이야기한다.",
    opening: "짝 잃은 양말은 자유로운 영혼일까, 길치일까?" },
  { id: "pillow-job", kind: "엉뚱한 토론", brief: "베개의 직업을 상상하는 짧고 장난스러운 대화를 한다.",
    opening: "베개의 직업은 경호원일까, 상담사일까?" },
  { id: "today-subtitle", kind: "다정한 질문", brief: "하루를 영화의 자막처럼 표현하게 한다. 평가하거나 성과를 묻지 않는다.",
    opening: "오늘 하루에 짧은 자막 하나 붙이면 뭐라고 쓸래?" },
  { id: "small-happy", kind: "다정한 질문", brief: "오늘의 사소하고 기분 좋은 감각을 가볍게 묻는다. 답을 재촉하지 않는다.",
    opening: "오늘 제일 좋았던 냄새나 소리, 하나 떠오르는 거 있어?" },
  { id: "imaginary-bouquet", kind: "다정한 질문", brief: "말이나 분위기로 가상의 꽃다발을 고르는 친밀한 대화를 한다.",
    opening: "말로 꽃다발을 만들 수 있다면, 오늘은 어떤 단어를 넣어줄까?" },
  { id: "restaurant-name", kind: "이름 짓기", brief: "둘만의 가상 식당 이름을 함께 만든다.",
    opening: "상상 속 식당을 하나 열자. 이름이 너무 웃겨도 괜찮다면 뭐로 할까?" },
  { id: "secret-handshake", kind: "이름 짓기", brief: "관계 독점 없이 가상의 재미있는 인사말을 함께 만든다.",
    opening: "안녕 대신 이상한 인사말 하나 만들어 볼까? 첫 단어 추천해 줘." },
  { id: "cloud-pet-name", kind: "이름 짓기", brief: "가상의 구름 반려동물에게 이름을 지어주는 놀이를 한다.",
    opening: "구름을 반려동물로 키운다고 상상해 봐. 이름은 뭐가 어울릴까?" }
];

export const conversationHistoryLimit = 12;

export function chooseConversation(recentIds: readonly string[] = [], pick: (max: number) => number = randomInt): ConversationPlan {
  const recent = recentIds.slice(-conversationHistoryLimit);
  const lastKind = conversationIdeas.find(idea => idea.id === recent.at(-1))?.kind;
  const unseen = conversationIdeas.filter(idea => !recent.includes(idea.id));
  const varied = unseen.filter(idea => idea.kind !== lastKind);
  const candidates = varied.length ? varied : unseen.length ? unseen : conversationIdeas;
  const index = pick(candidates.length);
  if (!Number.isInteger(index) || index < 0 || index >= candidates.length) throw new Error("Invalid conversation selection");
  return { ...candidates[index]! };
}

export function nextConversationHistory(recent: readonly string[], plan: ConversationPlan): string[] {
  return [...recent, plan.id].slice(-conversationHistoryLimit);
}
