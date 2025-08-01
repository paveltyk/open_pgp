defmodule OpenPGP.Util do
  @moduledoc """
  Provides a set of utility functions to work with data.
  """

  alias OpenPGP.Packet
  alias OpenPGP.Packet.BodyChunk, as: BChunk

  @type public_key_algo_tuple :: {1..255, binary()}
  @type sym_algo_tuple :: {byte(), binary()}
  @type compression_algo_tuple :: {byte(), binary()}

  @doc """
  Decode Multiprecision integer (MPI) given input binary.
  Return MPI value and remaining binary.

  ## [RFC4880](https://www.ietf.org/rfc/rfc4880.txt)

  ### 3.2.  Multiprecision Integers

  Multiprecision integers (also called MPIs) are unsigned integers used
  to hold large integers such as the ones used in cryptographic
  calculations.

  An MPI consists of two pieces: a two-octet scalar that is the length
  of the MPI in bits followed by a string of octets that contain the
  actual integer.

  These octets form a big-endian number; a big-endian number can be
  made into an MPI by prefixing it with the appropriate length.

  Examples:

  (all numbers are in hexadecimal)

  The string of octets [00 01 01] forms an MPI with the value 1.  The
  string [00 09 01 FF] forms an MPI with the value of 511.

  Additional rules:

  The size of an MPI is ((MPI.length + 7) / 8) + 2 octets.

  The length field of an MPI describes the length starting from its
  most significant non-zero bit.  Thus, the MPI [00 02 01] is not
  formed correctly.  It should be [00 01 01].

  Unused bits of an MPI MUST be zero.

  Also note that when an MPI is encrypted, the length refers to the
  plaintext MPI.  It may be ill-formed in its ciphertext.
  """
  @spec decode_mpi(<<_::16, _::_*8>>) :: {mpi_value :: binary(), rest :: binary()}
  def decode_mpi(<<mpi_length::16, rest::binary>>) do
    octets_count = floor((mpi_length + 7) / 8)
    <<mpi_value::bytes-size(octets_count), next::binary>> = rest

    {mpi_value, next}
  end

  @doc """
  Inverse of `.decode_mpi/1`. Takes an MPI value, and encode it as MPI
  binary.

  ### Example:

      iex> OpenPGP.Util.encode_mpi(<<0x1>>)
      <<0, 0x1, 0x1>>

      iex> OpenPGP.Util.encode_mpi(<<0x1, 0xFF>>)
      <<0x0, 0x9, 0x1, 0xFF>>

      iex> :crypto.strong_rand_bytes(65536) |> OpenPGP.Util.encode_mpi()
      ** (RuntimeError) big-endian is too long
  """
  @spec encode_mpi(big_endian :: binary()) :: mpi :: <<_::16, _::_*8>>
  def encode_mpi("" <> _ = big_endian) do
    if byte_size(big_endian) > 65535, do: raise("big-endian is too long")

    bit_list = for <<bit::1 <- big_endian>>, do: bit
    bit_count = bit_list |> Enum.drop_while(&(&1 == 0)) |> length()

    <<bit_count::16, big_endian::binary>>
  end

  @doc """
  Concatenates packet body given a Packet or a list of BodyChunks.
  """
  @spec concat_body([BChunk.t()] | Packet.t()) :: bitstring()
  def concat_body(%Packet{body: chunks}) when is_list(chunks), do: do_concat_body(chunks, "")
  def concat_body(chunks) when is_list(chunks), do: do_concat_body(chunks, "")
  defp do_concat_body([%BChunk{data: data} | rest], acc), do: do_concat_body(rest, acc <> data)
  defp do_concat_body([], acc), do: acc

  @public_key_algos %{
    1 => "RSA (Encrypt or Sign) [HAC]",
    2 => "RSA Encrypt-Only [HAC]",
    3 => "RSA Sign-Only [HAC]",
    16 => "Elgamal (Encrypt-Only) [ELGAMAL] [HAC]",
    17 => "DSA (Digital Signature Algorithm) [FIPS186] [HAC]",
    18 => "ECDH public key algorithm",
    19 => "ECDSA public key algorithm [FIPS186]",
    20 => "Reserved (formerly Elgamal Encrypt or Sign)",
    21 => "Reserved for Diffie-Hellman (X9.42, as defined for IETF-S/MIME)",
    22 => "EdDSA [RFC8032]",
    23 => "Reserved for AEDH",
    24 => "Reserved for AEDSA",
    100 => "Private/Experimental algorithm",
    101 => "Private/Experimental algorithm",
    102 => "Private/Experimental algorithm",
    103 => "Private/Experimental algorithm",
    104 => "Private/Experimental algorithm",
    105 => "Private/Experimental algorithm",
    106 => "Private/Experimental algorithm",
    107 => "Private/Experimental algorithm",
    108 => "Private/Experimental algorithm",
    109 => "Private/Experimental algorithm",
    110 => "Private/Experimental algorithm"
  }
  @public_key_ids Map.keys(@public_key_algos)

  @pk_algo_error """
  Expected public key algo ID to be one of:
  #{@public_key_algos |> Enum.map(&"#{elem(&1, 0)} - #{elem(&1, 1)}") |> Enum.join("\n")}
  """

  @doc """
  Convert public-key algorithm ID to a tuple with ID and name binary.

  ---

  RFC4880 (https://www.ietf.org/rfc/rfc4880.txt)

  9.1.  Public-Key Algorithms
  +-----------+----------------------------------------------------+
  |        ID | Algorithm                                          |
  +-----------+----------------------------------------------------+
  |         1 | RSA (Encrypt or Sign) [HAC]                        |
  |         2 | RSA Encrypt-Only [HAC]                             |
  |         3 | RSA Sign-Only [HAC]                                |
  |        16 | Elgamal (Encrypt-Only) [ELGAMAL] [HAC]             |
  |        17 | DSA (Digital Signature Algorithm) [FIPS186] [HAC]  |
  |        18 | ECDH public key algorithm                          |
  |        19 | ECDSA public key algorithm [FIPS186]               |
  |        20 | Reserved (formerly Elgamal Encrypt or Sign)        |
  |        21 | Reserved for Diffie-Hellman                        |
  |           | (X9.42, as defined for IETF-S/MIME)                |
  |        22 | EdDSA [RFC8032]                                    |
  |        23 | Reserved for AEDH                                  |
  |        24 | Reserved for AEDSA                                 |
  |  100--110 | Private/Experimental algorithm                     |
  +-----------+----------------------------------------------------+
  """
  @spec public_key_algo_tuple(1..255) :: public_key_algo_tuple()
  def public_key_algo_tuple(algo) when algo in @public_key_ids,
    do: {algo, @public_key_algos[algo]}

  def public_key_algo_tuple(algo), do: raise(@pk_algo_error <> "\nGot: #{inspect(algo)}")

  @sym_algos %{
    # => {name, cipher_block_size, key_size}
    0 => {"Plaintext or unencrypted data", 0, 0},
    1 => {"IDEA [IDEA]", 64, 128},
    2 => {"TripleDES (DES-EDE, [SCHNEIER] [HAC] - 168 bit key derived from 192)", 64, 192},
    3 => {"CAST5 (128 bit key, as per [RFC2144])", 64, 128},
    4 => {"Blowfish (128 bit key, 16 rounds) [BLOWFISH]", 64, 128},
    5 => {"Reserved", nil, nil},
    6 => {"Reserved", nil, nil},
    7 => {"AES with 128-bit key [AES]", 128, 128},
    8 => {"AES with 192-bit key", 128, 192},
    9 => {"AES with 256-bit key", 128, 256},
    10 => {"Twofish with 256-bit key [TWOFISH]", 128, 256},
    11 => {"Camellia with 128-bit key [RFC3713]", 128, 128},
    12 => {"Camellia with 192-bit key", 128, 192},
    13 => {"Camellia with 256-bit key", 128, 256},
    100 => {"Private/Experimental algorithm", nil, nil},
    101 => {"Private/Experimental algorithm", nil, nil},
    102 => {"Private/Experimental algorithm", nil, nil},
    103 => {"Private/Experimental algorithm", nil, nil},
    104 => {"Private/Experimental algorithm", nil, nil},
    105 => {"Private/Experimental algorithm", nil, nil},
    106 => {"Private/Experimental algorithm", nil, nil},
    107 => {"Private/Experimental algorithm", nil, nil},
    108 => {"Private/Experimental algorithm", nil, nil},
    109 => {"Private/Experimental algorithm", nil, nil},
    110 => {"Private/Experimental algorithm", nil, nil}
  }
  @sym_algo_ids Map.keys(@sym_algos)

  @sym_algo_error """
  Expected sym. algo ID to be one of:
  #{@sym_algos |> Enum.map(&"#{elem(&1, 0)} - #{elem(elem(&1, 1), 0)}") |> Enum.join("\n")}
  """

  @doc """
  Convert symmetric encryption algorithm ID to a tuple with ID and name binary.

  ---

  RFC4880 (https://www.ietf.org/rfc/rfc4880.txt)

  9.3.  Symmetric-Key Algorithms
  +-----------+-----------------------------------------------+
  |        ID | Algorithm                                     |
  +-----------+-----------------------------------------------+
  |         0 | Plaintext or unencrypted data                 |
  |         1 | IDEA [IDEA]                                   |
  |         2 | TripleDES (DES-EDE, [SCHNEIER] [HAC]          |
  |           | - 168 bit key derived from 192)               |
  |         3 | CAST5 (128 bit key, as per [RFC2144])         |
  |         4 | Blowfish (128 bit key, 16 rounds) [BLOWFISH]  |
  |         5 | Reserved                                      |
  |         6 | Reserved                                      |
  |         7 | AES with 128-bit key [AES]                    |
  |         8 | AES with 192-bit key                          |
  |         9 | AES with 256-bit key                          |
  |        10 | Twofish with 256-bit key [TWOFISH]            |
  |        11 | Camellia with 128-bit key [RFC3713]           |
  |        12 | Camellia with 192-bit key                     |
  |        13 | Camellia with 256-bit key                     |
  |  100--110 | Private/Experimental algorithm                |
  +-----------+-----------------------------------------------+
  """
  @spec sym_algo_tuple(byte()) :: sym_algo_tuple()
  def sym_algo_tuple(algo) when algo in @sym_algo_ids, do: {algo, elem(@sym_algos[algo], 0)}
  def sym_algo_tuple(algo), do: raise(@sym_algo_error <> "\nGot: #{inspect(algo)}")

  @doc """
  Detects cipher block size (bits) given symmetric encryption algorithm ID or a tuple.
  """
  @spec sym_algo_cipher_block_size(byte() | sym_algo_tuple()) :: non_neg_integer()
  def sym_algo_cipher_block_size({algo, _}), do: sym_algo_cipher_block_size(algo)
  def sym_algo_cipher_block_size(algo) when algo in @sym_algo_ids, do: elem(@sym_algos[algo], 1)
  def sym_algo_cipher_block_size(algo), do: raise(@sym_algo_error <> "\nGot: #{inspect(algo)}")

  @doc """
  Detects cipher key size (bits) given symmetric encryption algorithm ID or a tuple.
  """
  @spec sym_algo_key_size(byte() | sym_algo_tuple()) :: non_neg_integer()
  def sym_algo_key_size({algo, _}), do: sym_algo_key_size(algo)
  def sym_algo_key_size(algo) when algo in @sym_algo_ids, do: elem(@sym_algos[algo], 2)
  def sym_algo_key_size(algo), do: raise(@sym_algo_error <> "\nGot: #{inspect(algo)}")

  @comp_algos %{
    0 => "Uncompressed",
    1 => "ZIP [RFC1951]",
    2 => "ZLIB [RFC1950]",
    3 => "BZip2 [BZ2]",
    100 => "Private/Experimental algorithm",
    101 => "Private/Experimental algorithm",
    102 => "Private/Experimental algorithm",
    103 => "Private/Experimental algorithm",
    104 => "Private/Experimental algorithm",
    105 => "Private/Experimental algorithm",
    106 => "Private/Experimental algorithm",
    107 => "Private/Experimental algorithm",
    108 => "Private/Experimental algorithm",
    109 => "Private/Experimental algorithm",
    110 => "Private/Experimental algorithm"
  }
  @comp_algo_ids Map.keys(@comp_algos)

  @doc """
  Convert compression algorithm ID to a tuple with ID and name binary.

  ---

  RFC4880 (https://www.ietf.org/rfc/rfc4880.txt)

  9.3.  Compression Algorithms

      ID           Algorithm
      --           ---------
      0          - Uncompressed
      1          - ZIP [RFC1951]
      2          - ZLIB [RFC1950]
      3          - BZip2 [BZ2]
      100 to 110 - Private/Experimental algorithm
  """
  @spec compression_algo_tuple(byte()) :: compression_algo_tuple()
  def compression_algo_tuple(algo) when algo in @comp_algo_ids, do: {algo, @comp_algos[algo]}

  @v06x_note """
  As of 0.6.x supported sym.key ciphers are:

    1. 7 (AES with 128-bit key) in CFB mode
    1. 8 (AES with 192-bit key) in CFB mode
    1. 9 (AES with 256-bit key) in CFB mode
  """
  @spec sym_algo_to_crypto_cipher(sym_algo_tuple() | byte()) :: :aes_128_cfb128 | :aes_192_cfb128 | :aes_256_cfb128
  def sym_algo_to_crypto_cipher({algo, _}), do: sym_algo_to_crypto_cipher(algo)
  def sym_algo_to_crypto_cipher(7), do: :aes_128_cfb128
  def sym_algo_to_crypto_cipher(8), do: :aes_192_cfb128
  def sym_algo_to_crypto_cipher(9), do: :aes_256_cfb128
  def sym_algo_to_crypto_cipher(algo), do: raise(@v06x_note <> "\n Got: #{inspect(algo)}")

  @doc """
  Calculate a two-octet checksum, which is equal to the sum of the
  input binary octets modulo 65536.

  ### Example:

      iex> OpenPGP.Util.checksum(<<1::8, 2::8, 3::8>>)
      <<6::16>>
  """
  @spec checksum(binary()) :: <<_::16>>
  def checksum("" <> _ = binary) do
    for <<byte::8 <- binary>>, reduce: <<0::16>> do
      <<acc::16>> -> <<rem(acc + byte, 65536)::16>>
    end
  end
end
