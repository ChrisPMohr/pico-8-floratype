Flower genome, sprites (phenotype), and placement all take some combination of RAM, cart space, sprite sheet space, and map space. This outlines some ideas how we can effectively manage these

## Requirements

Flower genomes have to be stored in the available in game RAM, as well as be saved to the cart. This is the core data for a flower. We are currently allocating 4 bytes for genes for a flower. I am including all flower data in this, even that which is not strictly a gene: flower type and age.

We estimate that we'd want to have 5 8x7 grids (280) - 4 normal fields plus on for display / show - , plus some extras (estimate 40) for things like moving flowers, saving seeds, etc. That makes 1280 bytes in cart data for genomes.

RAM capacity isn't a consideration for that amount of space, but we do need to figure out what data structures make sense for all of this. PICO-8's numbers are 4 bytes, so we could use them as numbers directly, but this could pose a problem, as calculations assume signed, fixed point binary numbers, rather than unsigned ints. I think I may be able to make bitwise operations work correctly, as there is a "logical shift right" operator that ignores the sign.

---

Because we aim to be able to **deterministically** create sprites from a flower's genes, we should not need to store the sprites in the cart memory. However, we probably want them available in a sprite sheet to be able to efficiently draw them.

One 8x7 field of flowers contains 56 16x16 sprites, so 224 8x8 sprites. The entire available sprite sheet is 256 sprites, so if we put them in the main sprite sheet, there would be little room for anything else. Instead, we can use one of the extended sprite sheets in the extended RAM buffers (0x8000-0xffff). Interacting with these using regular sprite commands requires poking a particular memory value (`0x5f54`).

The biggest problems I am currently envisioning are:
1. How to populate this sheet, since it using sprite command with it precludes also using them with the regular sheet. The bottom 16 pixels of the sheet are unused, so I think we could copy the relevant templates into that space when writing to the sheet.
2. Load times when switching to a field. I don't know how long it would take to create 56 sprites. This is testable
3. Scrolling smoothly between fields isn't easy/possible with the current design. Vertical scrolling doesn't seem that hard by copying the existing memory up/down and writing a new row of sprites. I guess this could be done with horizontal scrolling as well, but requires moving 7 rows separately. Load times could be an issue here too.

I currently don't know how we could / would want to use the other extended RAM buffers. Notably, if we want 4 normal fields plus an extra one for shows, there's not enough space to fit all of the sprites at once.

---

I have so far imagined "placement", which flower goes where, as being somewhat implicit in both the sprite sheet and the cart memory. I think this is somewhat a problem for both, but the cart memory part is more obvious to me. Presumably, all 0s will be a valid flower, so how will we distinguish empty entries from that "zero flower"?

The options that occur to me now are either:
1. Store the position with every flower - this is efficient when the number of flowers is small, but as we grow towards the maximum, will take up some substantial amount of space. TODO: figure out how much
2. Binary encoding sort of things - for example, each flower entry in cart memory either starts with a 0, indicating a flower, or a 1, indicating empty. Again, this saves space at small number of flowers, but adds 1/32 space when full. That's an extra 40 bytes at current estimates, which isn't crazy. One downside of either of the above is that the flower data isn't aligned at byte boundaries, which I think is kind of a pain to deal with
3. Pick some value that isn't allowed (could be all 0s, all 1s, or anything else). Store that value for a missing flower. Then an empty field space takes exactly the same amount of memory as a full one.

Placement in the sprite sheet should almost certainly be based on the layout of the memory, since that's how the sspr function works. One thing to consider is that doesn't work nicely with some implementation of scrolling fields (see above)

I think representing placement in RAM will be a consequence of whatever data structure represents fields, held plants, etc.

## Design

### Migration Order
* Switch out gene storage from flags and placement from map -> LUA data
	- [x] generate_and_place_flower
	- [x] generate_flower
	- [x] place_flower
		- [x] not necessary, call field place directly
	- [x] kill_flower
	- [x] draw_flowers
		- [x] doesn't need metadata
	- [x] time_passes (and all nested calls)
	- [x] breed
	- [x] is_compatible
	- [x] get_genes
		- [x] Not necessary- read field directly

* Switch out sprite storage from default page -> generated in extended memory
	- [x] generate_and_place_flower
		- [x] doesn't directly affect sprites
	- [x] generate_flower
		- [x] doesn't directly affect sprites
	- [x] create flower
		- [x] I don't think we need to generate the sprite until we place the flower
		- [x] Step 2 - remove writes to sprite map
	- [x] place_flower
		- [x] Step 1 - generate sprite and write to extended sprite sheet
		- [x] Step 2 - Remove writes to map
	- [x] kill_flower
		- [x] Step 1 - Write blanks to the extended sprite sheet
		- [x] Step 2 - Remove writes to map
	- [x] draw_flowers
		- [x] Step 1 - Draw extended sprite sheet 
	- [x] time_passes (and all nested calls)
		- [x] Validate that this is using updated methods above correctly
* Rewrite save tool - actually two pieces of functionality
	* New implementation that exports a field worth of sprite and genes to the spritesheet
	* Cart storage / loading of genome data

#### Cleanup steps
- [x] Adjust field (and button?) cursor indexing to be 1 based
- [x] Try switching genes to single 32 bit value instead of table
- [x] Remove/refactor/rename functions with overlapping uses
	- [x] create_flower
	- [x] field1:place
	- [x] place_flower
	- [x] create_and_place_flower_sprite
	- [x] kill_flower
	- [x] remove_flower


### Functions to Change
```
generate_and_place_flower
generate_flower
place_flower
kill_flower
draw_flowers
save_game
time_passes (and all nested calls)
breed
is_compatible
get_genes
```
### Data Structures
* Plant
	* field_n - which field
	* pos - x, y coords in the field
	* genes - see note above about what type to use
* Field
	* flowers - list of list of plants. Fixed array size. Empty plots are a nil value.
	* Maybe some position data, but unclear how that would work for the non-contiguous field for "Flower Show"