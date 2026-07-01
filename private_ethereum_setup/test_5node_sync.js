const { ethers } = require('ethers');

const NODE_COUNT = parseInt(process.env.NODE_COUNT || '5', 10);

async function getBlockNumber(port) {
  const provider = new ethers.providers.JsonRpcProvider(`http://127.0.0.1:${port}`);
  return provider.getBlockNumber();
}

async function main() {
  console.log(`Checking all ${NODE_COUNT} Geth nodes are reachable and in sync...\n`);

  const results = [];
  for (let i = 1; i <= NODE_COUNT; i++) {
    const port = 18544 + i;
    try {
      const block = await getBlockNumber(port);
      results.push({ node: i, port, block });
    } catch (e) {
      results.push({ node: i, port, error: e.message });
    }
  }

  let maxBlock = 0;
  for (const r of results) {
    if (r.block !== undefined) {
      maxBlock = Math.max(maxBlock, r.block);
    }
  }

  for (const r of results) {
    if (r.error) {
      console.log(`Node ${r.node} (port ${r.port}): UNREACHABLE - ${r.error}`);
    } else {
      const lag = maxBlock - r.block;
      const status = lag <= 1 ? 'OK' : `LAGGING (${lag} blocks behind)`;
      console.log(`Node ${r.node} (port ${r.port}): block ${r.block} - ${status}`);
    }
  }

  const reachable = results.filter(r => r.block !== undefined);
  const inSync = reachable.filter(r => maxBlock - r.block <= 1);

  if (reachable.length === 0) {
    console.error('\nNo nodes are reachable. Is the devnet running?');
    process.exit(1);
  }

  if (inSync.length === reachable.length) {
    console.log('\nAll reachable nodes are in sync.');
  } else {
    console.error('\nSome nodes are not in sync.');
    process.exit(1);
  }
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
