const { Client, GatewayIntentBits } = require("discord.js");

const PPQ_BASE = "https://api.ppq.ai";
const apiKey = process.env.OPENAI_API_KEY;
const botToken = process.env.DISCORD_BOT_TOKEN;

if (!apiKey || !botToken) {
  console.error("Missing OPENAI_API_KEY or DISCORD_BOT_TOKEN");
  process.exit(1);
}

const client = new Client({
  intents: [
    GatewayIntentBits.Guilds,
    GatewayIntentBits.GuildMessages,
    GatewayIntentBits.MessageContent,
  ],
});

async function checkBalance() {
  const res = await fetch(`${PPQ_BASE}/credits/balance`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: "{}",
  });
  if (!res.ok) throw new Error(`Balance API returned ${res.status}`);
  const data = await res.json();
  return data.balance;
}

async function createTopup(amount) {
  const res = await fetch(`${PPQ_BASE}/topup/create/btc-lightning`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ amount }),
  });
  if (!res.ok) throw new Error(`Topup API returned ${res.status}`);
  return res.json();
}

client.on("messageCreate", async (msg) => {
  if (msg.author.bot) return;
  const content = msg.content.trim();

  if (content === "!balance") {
    try {
      const balance = await checkBalance();
      await msg.channel.send(`\u26a1 ppq.ai balance: $${Number(balance).toFixed(2)}`);
    } catch (err) {
      console.error("Balance error:", err.message);
      await msg.channel.send(`Failed to check balance: ${err.message}. Try again?`);
    }
    return;
  }

  if (content.startsWith("!topup")) {
    const parts = content.split(/\s+/);
    let amount = 1.0;
    let isDefault = true;

    if (parts[1]) {
      const parsed = parseFloat(parts[1]);
      if (isNaN(parsed) || parsed <= 0) {
        await msg.channel.send("Usage: `!topup [amount]` (default $1.00)");
        return;
      }
      amount = parsed;
      isDefault = false;
    }

    const label = isDefault
      ? `$${amount.toFixed(2)} (default)`
      : `$${amount.toFixed(2)}`;

    try {
      await msg.channel.send(`\u26a1 Topping up ${label} via Bitcoin Lightning...`);
      const data = await createTopup(amount);
      const invoice = data.lightning_invoice;
      const checkout = data.checkout_url;

      let reply = `\`\`\`\n${invoice}\n\`\`\``;
      if (checkout) reply += `\nPay here: ${checkout}`;
      reply += "\n\nAfter paying, run `!balance` to confirm.";
      await msg.channel.send(reply);
    } catch (err) {
      console.error("Topup error:", err.message);
      await msg.channel.send(`Failed to create invoice: ${err.message}. Try again?`);
    }
  }
});

client.once("ready", () => {
  console.log(`Credit bot online as ${client.user.tag}`);
});

client.login(botToken);
