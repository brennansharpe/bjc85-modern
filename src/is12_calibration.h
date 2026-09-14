#ifndef IS12_CALIBRATION_H
#define IS12_CALIBRATION_H
#include <stdbool.h>
#include <stdint.h>
#define IS12_MEASUREMENT_SIZE 12337
#define IS12_CORRECTION_SIZE 2057
/* BJC-85 / non-A202 path, Canon normal tone factors, measured plain-paper
 * reference. This does not claim manufacturer-reference colour accuracy. */
bool is12_correction(const uint8_t measurement[IS12_MEASUREMENT_SIZE],
                    uint8_t reference_temperature,uint8_t current_temperature,
                    unsigned dpi,uint8_t parameters[IS12_CORRECTION_SIZE]);
bool is12_reference_save(const char *filename,const uint8_t *measurement,uint8_t temperature,
                         const char *serial,const uint8_t carrier[12]);
bool is12_reference_load(const char *filename,uint8_t *measurement,uint8_t *temperature,
                         const char *serial,const uint8_t carrier[12]);
#endif
