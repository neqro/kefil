import fs from 'node:fs';
import solc from 'solc';
import ganache from 'ganache';
import { ethers } from 'ethers';
import assert from 'node:assert/strict';

const src = (f) => ({ content: fs.readFileSync(`contracts/${f}`, 'utf8') });
const input = {
  language: 'Solidity',
  sources: { 'Kefil.sol': src('Kefil.sol'), 'MockAgentID.sol': src('MockAgentID.sol') },
  settings: { optimizer: { enabled: true, runs: 200 }, evmVersion: 'paris',
    outputSelection: { '*': { '*': ['abi', 'evm.bytecode.object'] } } },
};
const out = JSON.parse(solc.compile(JSON.stringify(input)));
const errs = (out.errors || []).filter((e) => e.severity === 'error');
if (errs.length) { console.error(errs); process.exit(1); }
(out.errors || []).forEach((e) => console.log('warn:', e.formattedMessage.split('\n')[0]));
fs.mkdirSync('build', { recursive: true });
const K = out.contracts['Kefil.sol'].Kefil;
fs.writeFileSync('build/Kefil.json', JSON.stringify({ abi: K.abi, bytecode: '0x' + K.evm.bytecode.object }, null, 1));
fs.writeFileSync('build/standard-input.json', JSON.stringify({ ...input, sources: { 'Kefil.sol': input.sources['Kefil.sol'] } }, null, 1));

const provider = new ethers.BrowserProvider(ganache.provider({ logging: { quiet: true }, wallet: { totalAccounts: 10 } }));
const s = await Promise.all([...Array(10).keys()].map((i) => provider.getSigner(i)));
const M = out.contracts['MockAgentID.sol'].MockAgentID;
const mock = await new ethers.ContractFactory(M.abi, M.evm.bytecode.object, s[0]).deploy();
const kefil = await new ethers.ContractFactory(K.abi, K.evm.bytecode.object, s[0]).deploy(await mock.getAddress());
const A = await Promise.all(s.map((x) => x.getAddress()));
for (let i = 0; i < 9; i++) await (await mock.set(A[i], 1)).wait(); // A[9] has no Agent ID
const k = (i) => kefil.connect(s[i]);
const rejects = async (p, name) => { await assert.rejects(p, (e) => String(e.shortMessage || e.message).includes(name) || JSON.stringify(e).includes(kefil.interface.getError(name).selector)); };

// vouch basics
await (await k(1).vouch(A[0], 'iyi ajan')).wait();
await (await k(2).vouch(A[0], '')).wait();
assert.equal(await kefil.trustScore(A[0]), 20n);
await rejects(k(1).vouch(A[0], ''), 'AlreadyDone');
await rejects(k(1).vouch(A[1], ''), 'SelfAction');
await rejects(k(1).vouch(A[9], ''), 'NoAgentId');
await rejects(k(9).vouch(A[1], ''), 'NoAgentId');
await rejects(k(1).vouch(A[2], 'x'.repeat(141)), 'NoteTooLong');

// revoke with swap-and-pop
await (await k(3).vouch(A[0], '')).wait();
await (await k(1).revokeVouch(A[0])).wait();
assert.deepEqual([...(await kefil.vouchersOf(A[0]))].sort(), [A[2], A[3]].sort());
assert.equal(await kefil.hasVouched(A[1], A[0]), false);
try { await k(1).revokeVouch.staticCall(A[0]); console.log('NO REVERT', await kefil.hasVouched(A[1],A[0])); } catch(e){ console.log('revert ok', e.shortMessage, e.revert?.name); }

// flags + risky + bad-vouch penalty for vouchers
await (await k(4).vouch(A[8], '')).wait(); // A4 vouches for A8 who will turn out bad
for (const i of [1, 2, 3, 5, 6]) await (await k(i).flag(A[8], 'rug')).wait();
assert.equal(await kefil.isRisky(A[8]), true);
assert.equal(await kefil.badVouches(A[4]), 1n);
assert.equal(await kefil.trustScore(A[4]), -15n);
// risky voucher's vouches stop counting
await (await k(8).vouch(A[0], '')).wait();
assert.equal(await kefil.validVouchesIn(A[0]), 2n);
await rejects(k(1).flag(A[8], ''), 'AlreadyDone');
await (await k(1).revokeFlag(A[8])).wait();
assert.equal(await kefil.isRisky(A[8]), false);
assert.equal(await kefil.validVouchesIn(A[0]), 3n);

// losing Agent ID: score 0 and vouches from it stop counting
await (await mock.set(A[2], 0)).wait();
assert.equal(await kefil.trustScore(A[2]), 0n);
assert.equal(await kefil.validVouchesIn(A[0]), 2n);

// gate
assert.equal(await kefil.isTrusted(A[0], 20), true);
assert.equal(await kefil.isTrusted(A[0], 30), false);

// max vouches out
await (await mock.set(A[2], 1)).wait();
const extra = [];
for (let i = 0; i < 20; i++) { const w = ethers.Wallet.createRandom(); extra.push(w.address); await (await mock.set(w.address, 1)).wait(); }
for (let i = 0; i < 20; i++) await (await k(7).vouch(extra[i], '')).wait();
await rejects(k(7).vouch(A[0], ''), 'TooManyVouches');

const p = await kefil.profile(A[0]);
console.log('profile A0:', p.map(String).join(', '));
const g = await (await k(5).vouch(A[0], 'test')).wait();
console.log('vouch gas:', g.gasUsed.toString());
console.log('ALL TESTS PASSED');
process.exit(0);
