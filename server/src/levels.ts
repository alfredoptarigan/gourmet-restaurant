// GameWorld.LEVEL_THRESHOLDS from the original client: the gourmet points each level starts
// at and the coins paid for reaching it. Level 1 is the first row.
// The client keeps its own copy (levels.gd) for display; the server's copy decides rewards.
export const LEVELS: readonly { points: number; coinReward: number }[] = [
  { points: 0, coinReward: 0 },
  { points: 50, coinReward: 3500 },
  { points: 70, coinReward: 2500 },
  { points: 100, coinReward: 1000 },
  { points: 200, coinReward: 1000 },
  { points: 500, coinReward: 1000 },
  { points: 1000, coinReward: 1000 },
  { points: 2000, coinReward: 1000 },
  { points: 4000, coinReward: 1000 },
  { points: 6000, coinReward: 1000 },
  { points: 8000, coinReward: 1000 },
  { points: 10000, coinReward: 1000 },
  { points: 14000, coinReward: 1000 },
  { points: 18000, coinReward: 1000 },
  { points: 22000, coinReward: 1000 },
  { points: 30000, coinReward: 1000 },
  { points: 38000, coinReward: 1000 },
  { points: 46000, coinReward: 1000 },
  { points: 58000, coinReward: 1000 },
  { points: 70000, coinReward: 1000 },
  { points: 86000, coinReward: 1000 },
  { points: 102000, coinReward: 1000 },
  { points: 122000, coinReward: 1000 },
  { points: 142000, coinReward: 1000 },
  { points: 166000, coinReward: 1000 },
  { points: 190000, coinReward: 1000 },
  { points: 218000, coinReward: 1000 },
  { points: 246000, coinReward: 1000 },
  { points: 280000, coinReward: 1000 },
  { points: 320000, coinReward: 1000 },
  { points: 370000, coinReward: 1000 },
  { points: 430000, coinReward: 1000 },
  { points: 500000, coinReward: 1000 },
  { points: 580000, coinReward: 1000 },
  { points: 661000, coinReward: 1000 },
  { points: 743000, coinReward: 1000 },
  { points: 826000, coinReward: 1000 },
  { points: 910000, coinReward: 1000 },
  { points: 995000, coinReward: 1000 },
  { points: 1081000, coinReward: 1000 },
  { points: 1168000, coinReward: 1000 },
  { points: 1256000, coinReward: 1000 },
  { points: 1345000, coinReward: 1000 },
  { points: 1435000, coinReward: 1000 },
  { points: 1526000, coinReward: 1000 },
  { points: 1618000, coinReward: 1000 },
  { points: 1711000, coinReward: 1000 },
  { points: 1805000, coinReward: 1000 },
  { points: 1900000, coinReward: 1000 },
  { points: 1996000, coinReward: 1000 },
  { points: 2093000, coinReward: 1000 },
  { points: 2191000, coinReward: 1000 },
  { points: 2290000, coinReward: 1000 },
  { points: 2390000, coinReward: 1000 },
  { points: 2491000, coinReward: 1000 },
  { points: 2593000, coinReward: 1000 },
  { points: 2696000, coinReward: 1000 },
  { points: 2800000, coinReward: 1000 },
  { points: 2905000, coinReward: 1000 },
  { points: 3011000, coinReward: 1000 },
  { points: 3118000, coinReward: 1000 },
  { points: 3226000, coinReward: 1000 },
  { points: 3335000, coinReward: 1000 },
  { points: 3445000, coinReward: 1000 },
  { points: 3556000, coinReward: 1000 },
  { points: 3668000, coinReward: 1000 },
];

export function levelFor(gourmetPoints: number): number {
  let level = 1;
  while (level < LEVELS.length && gourmetPoints >= LEVELS[level].points) {
    level += 1;
  }
  return level;
}

/** Coins paid for moving from one level to a higher one: the reward of every level entered. */
export function rewardBetween(fromLevel: number, toLevel: number): number {
  return LEVELS.slice(fromLevel, toLevel).reduce((total, level) => total + level.coinReward, 0);
}
