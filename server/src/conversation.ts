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
    opening: "손바닥만 한 용이 왔어, 이름 뭐로 할까?" },
  { id: "cat-for-mayor", kind: "상상", brief: "고양이가 동네 시장이 된 세계의 첫 정책을 함께 만든다.",
    opening: "고양이가 시장이 됐어, 첫 공약은?" },
  { id: "moon-picnic", kind: "상상", brief: "달에서 소풍을 한다는 가상의 상황에서 엉뚱한 준비물을 고른다.",
    opening: "달로 소풍 간다면, 간식은 뭐 챙길래?" },
  { id: "tiny-superpower", kind: "선택 놀이", brief: "쓸모가 작고 귀여운 초능력 두 가지 중 하나를 고르고 이유를 듣는다.",
    opening: "초능력 하나, 과자 조용히 뜯기야 이불 온도야?" },
  { id: "rain-soundtrack", kind: "선택 놀이", brief: "비 오는 날 어울리는 분위기를 선택하게 하고 취향을 이야기한다.",
    opening: "비 오는 날, 재즈야 영화 음악이야?" },
  { id: "one-silly-rule", kind: "선택 놀이", brief: "하루 동안 세계에 적용할 무해하고 엉뚱한 규칙을 함께 고른다.",
    opening: "엘리베이터가 인사하면 뭐라고 답할래?" },
  { id: "cloud-complaint", kind: "미니 상황극", brief: "가상의 구름 고객센터로 시작하되 실제 상황이라고 속이지 않는다.",
    opening: "구름 고객센터야, 하늘에 뭐 요청할래?" },
  { id: "bread-interview", kind: "미니 상황극", brief: "빵집에 취직하려는 가상의 크루아상을 면접하는 역할 놀이를 한다.",
    opening: "크루아상 면접 본대, 첫 질문은?" },
  { id: "alien-tour-guide", kind: "미니 상황극", brief: "처음 지구에 온 외계인에게 평범한 물건 하나를 설명하는 놀이를 한다.",
    opening: "외계인에게 베개를 한마디로 설명해 줄래?" },
  { id: "penguin-ending", kind: "짧은 이야기", brief: "가상 펭귄이 카페를 차리는 짧은 이야기의 다음 장면을 함께 만든다.",
    opening: "펭귄 카페의 첫 메뉴, 뭐가 웃길까?" },
  { id: "lost-moon-sock", kind: "짧은 이야기", brief: "달이 양말 한 짝을 잃어버린 동화 같은 설정의 결말을 함께 만든다.",
    opening: "달의 양말 한 짝이 사라졌어, 범인은?" },
  { id: "umbrella-holiday", kind: "짧은 이야기", brief: "가상 우산이 휴가를 간 이야기에서 예상 밖의 행선지를 만든다.",
    opening: "우산이 휴가 간대, 어디로 갈까?" },
  { id: "weekday-flavor", kind: "취향 발견", brief: "요일을 맛에 비유하는 가벼운 취향 대화를 한다.",
    opening: "오늘을 아이스크림 맛으로 고르면?" },
  { id: "sound-of-cozy", kind: "취향 발견", brief: "편안한 느낌을 주는 소리를 묻고 사용자의 느낌에 공감한다.",
    opening: "편한 소리 하나만, 빗소리야 끓는 물이야?" },
  { id: "room-title", kind: "취향 발견", brief: "지금 떠오르는 공간에 영화 제목을 붙이는 가벼운 대화를 한다. 현재 공간을 봤다고 말하지 않는다.",
    opening: "네 방이 영화라면 제목이 뭐야?" },
  { id: "sandwich-debate", kind: "엉뚱한 토론", brief: "샌드위치의 가장자리 같은 사소한 소재를 장난스럽게 토론한다.",
    opening: "샌드위치 모서리, 제일 맛있지 않아?" },
  { id: "socks-personality", kind: "엉뚱한 토론", brief: "양말에 성격이 있다면 어떨지 가볍게 이야기한다.",
    opening: "짝 잃은 양말은 자유인일까, 길치일까?" },
  { id: "pillow-job", kind: "엉뚱한 토론", brief: "베개의 직업을 상상하는 짧고 장난스러운 대화를 한다.",
    opening: "베개의 직업, 경호원이야 상담사야?" },
  { id: "today-subtitle", kind: "다정한 질문", brief: "하루를 영화의 자막처럼 표현하게 한다. 평가하거나 성과를 묻지 않는다.",
    opening: "오늘 하루에 자막 한 줄 붙이면 뭐야?" },
  { id: "small-happy", kind: "다정한 질문", brief: "오늘의 사소하고 기분 좋은 감각을 가볍게 묻는다. 답을 재촉하지 않는다.",
    opening: "오늘 좋았던 냄새 하나, 뭐였어?" },
  { id: "imaginary-bouquet", kind: "다정한 질문", brief: "말이나 분위기로 가상의 꽃다발을 고르는 친밀한 대화를 한다.",
    opening: "말로 꽃다발 만든다면 첫 단어는?" },
  { id: "restaurant-name", kind: "이름 짓기", brief: "둘만의 가상 식당 이름을 함께 만든다.",
    opening: "우리 가상 식당 이름, 뭐로 지을까?" },
  { id: "secret-handshake", kind: "이름 짓기", brief: "관계 독점 없이 가상의 재미있는 인사말을 함께 만든다.",
    opening: "이상한 인사말 하나 만들자, 첫 단어는?" },
  { id: "cloud-pet-name", kind: "이름 짓기", brief: "가상의 구름 반려동물에게 이름을 지어주는 놀이를 한다.",
    opening: "구름 반려동물 이름, 뭐로 할까?" }
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
