// SPDX-License-Identifier: GPL-2.0 OR MIT
/*
 * blake2s compatibility for kernels that already provide the blake2s library
 * (lib/crypto/blake2s.o) but lack the exported init/init_key/hmac symbols
 * that wireguard's zinc expects.  zinc's own blake2s copy is not built to
 * avoid duplicate symbols.
 */
#define blake2s_init_param __wg_kern_blake2s_init_param
#define blake2s_init __wg_kern_blake2s_init
#define blake2s_init_key __wg_kern_blake2s_init_key
#define blake2s __wg_kern_blake2s
#include <crypto/blake2s.h>
#undef blake2s_init_param
#undef blake2s_init
#undef blake2s_init_key
#undef blake2s

#include <linux/string.h>
#include <linux/kernel.h>
#include <linux/module.h>

int __init blake2s_mod_init(void)
{
	return 0;
}

void blake2s_init(struct blake2s_state *state, const size_t outlen)
{
	__wg_kern_blake2s_init(state, outlen);
}
EXPORT_SYMBOL(blake2s_init);

void blake2s_init_key(struct blake2s_state *state, const size_t outlen,
		      const void *key, const size_t keylen)
{
	__wg_kern_blake2s_init_key(state, outlen, key, keylen);
}
EXPORT_SYMBOL(blake2s_init_key);

void blake2s_hmac(u8 *out, const u8 *in, const u8 *key, const size_t outlen,
		  const size_t inlen, const size_t keylen)
{
	struct blake2s_state state;
	u8 x_key[BLAKE2S_BLOCK_SIZE] __aligned(__alignof__(u32)) = { 0 };
	u8 i_hash[BLAKE2S_HASH_SIZE] __aligned(__alignof__(u32));
	int i;

	if (keylen > BLAKE2S_BLOCK_SIZE) {
		blake2s_init(&state, BLAKE2S_HASH_SIZE);
		blake2s_update(&state, key, keylen);
		blake2s_final(&state, x_key);
	} else
		memcpy(x_key, key, keylen);

	for (i = 0; i < BLAKE2S_BLOCK_SIZE; ++i)
		x_key[i] ^= 0x36;

	blake2s_init(&state, BLAKE2S_HASH_SIZE);
	blake2s_update(&state, x_key, BLAKE2S_BLOCK_SIZE);
	blake2s_update(&state, in, inlen);
	blake2s_final(&state, i_hash);

	for (i = 0; i < BLAKE2S_BLOCK_SIZE; ++i)
		x_key[i] ^= 0x5c ^ 0x36;

	blake2s_init(&state, BLAKE2S_HASH_SIZE);
	blake2s_update(&state, x_key, BLAKE2S_BLOCK_SIZE);
	blake2s_update(&state, i_hash, BLAKE2S_HASH_SIZE);
	blake2s_final(&state, out);

	memzero_explicit(x_key, sizeof(x_key));
	memzero_explicit(i_hash, sizeof(i_hash));
	memzero_explicit(&state, sizeof(state));
}
EXPORT_SYMBOL(blake2s_hmac);