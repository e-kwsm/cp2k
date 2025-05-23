!--------------------------------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations                              !
!   Copyright 2000-2025 CP2K developers group <https://cp2k.org>                                   !
!                                                                                                  !
!   SPDX-License-Identifier: GPL-2.0-or-later                                                      !
!--------------------------------------------------------------------------------------------------!

! **************************************************************************************************
!> \brief Barostat structure: module containing barostat available for MD
!> \author teo [tlaino] - University of Zurich - 09.2007
! **************************************************************************************************
MODULE barostat_types
   USE cell_types,                      ONLY: cell_type
   USE extended_system_init,            ONLY: initialize_npt
   USE extended_system_types,           ONLY: npt_info_type
   USE force_env_types,                 ONLY: force_env_get,&
                                              force_env_type
   USE global_types,                    ONLY: global_environment_type
   USE input_constants,                 ONLY: npe_f_ensemble,&
                                              npe_i_ensemble,&
                                              nph_uniaxial_damped_ensemble,&
                                              nph_uniaxial_ensemble,&
                                              npt_f_ensemble,&
                                              npt_i_ensemble,&
                                              npt_ia_ensemble
   USE input_section_types,             ONLY: section_vals_get,&
                                              section_vals_get_subs_vals,&
                                              section_vals_type,&
                                              section_vals_val_get
   USE kinds,                           ONLY: dp
   USE simpar_types,                    ONLY: simpar_type
#include "../../base/base_uses.f90"

   IMPLICIT NONE

   INTEGER, PARAMETER, PUBLIC               :: do_clv_geo_center = 0, &
                                               do_clv_fix_point = 1, &
                                               do_clv_xyz = 0, &
                                               do_clv_x = 1, &
                                               do_clv_y = 2, &
                                               do_clv_z = 3, &
                                               do_clv_xy = 4, &
                                               do_clv_xz = 5, &
                                               do_clv_yz = 6

   PRIVATE
   PUBLIC :: barostat_type, &
             create_barostat_type, &
             release_barostat_type

! **************************************************************************************************
   TYPE barostat_type
      INTEGER                          :: ref_count = 0
      INTEGER                          :: virial_components = do_clv_geo_center
      REAL(KIND=dp)                    :: temp_ext = 0.0_dp
      TYPE(npt_info_type), POINTER  :: npt(:, :) => NULL()
      TYPE(section_vals_type), POINTER :: section => NULL()
   END TYPE barostat_type

! *** Global parameters ***

   CHARACTER(len=*), PARAMETER, PRIVATE :: moduleN = 'barostat_types'

CONTAINS

! **************************************************************************************************
!> \brief ...
!> \param barostat ...
!> \param md_section ...
!> \param force_env ...
!> \param simpar ...
!> \param globenv ...
!> \par History
!>      09.2007 created [tlaino]
!> \author Teodoro Laino
! **************************************************************************************************
   SUBROUTINE create_barostat_type(barostat, md_section, force_env, simpar, &
                                   globenv)
      TYPE(barostat_type), POINTER                       :: barostat
      TYPE(section_vals_type), POINTER                   :: md_section
      TYPE(force_env_type), POINTER                      :: force_env
      TYPE(simpar_type), POINTER                         :: simpar
      TYPE(global_environment_type), POINTER             :: globenv

      LOGICAL                                            :: check, explicit
      TYPE(cell_type), POINTER                           :: cell
      TYPE(section_vals_type), POINTER                   :: barostat_section

      check = .NOT. ASSOCIATED(barostat)
      CPASSERT(check)
      barostat_section => section_vals_get_subs_vals(md_section, "BAROSTAT")
      CALL section_vals_get(barostat_section, explicit=explicit)
      IF (simpar%ensemble == npt_i_ensemble .OR. &
          simpar%ensemble == npt_ia_ensemble .OR. &
          simpar%ensemble == npt_f_ensemble .OR. &
          simpar%ensemble == npe_f_ensemble .OR. &
          simpar%ensemble == npe_i_ensemble .OR. &
          simpar%ensemble == nph_uniaxial_ensemble .OR. &
          simpar%ensemble == nph_uniaxial_damped_ensemble) THEN
         ALLOCATE (barostat)
         barostat%ref_count = 1
         barostat%section => barostat_section
         NULLIFY (barostat%npt)
         CALL force_env_get(force_env, cell=cell)

         barostat%temp_ext = simpar%temp_baro_ext
         CALL section_vals_val_get(barostat_section, "TEMP_TOL", r_val=simpar%temp_baro_tol)
         ! Initialize or possibly restart Barostat
         CALL initialize_npt(simpar, globenv, barostat%npt, &
                             cell, work_section=barostat_section)

         ! If none of the possible barostat has been allocated let's deallocate
         ! the full structure
         IF (.NOT. ASSOCIATED(barostat%npt)) THEN
            CALL release_barostat_type(barostat)
         END IF

         ! User defined virial screening
         CALL section_vals_val_get(barostat_section, "VIRIAL", i_val=barostat%virial_components)
         check = barostat%virial_components == do_clv_xyz .OR. simpar%ensemble == npt_f_ensemble
         IF (.NOT. check) &
            CALL cp_abort(__LOCATION__, "The screening of the components of "// &
                          "the virial is available only with the NPT_F ensemble!")
      ELSE
         IF (explicit) &
            CALL cp_warn(__LOCATION__, &
                         "A barostat has been defined with an MD ensemble which does not support barostat! "// &
                         "Its definition will be ignored!")
      END IF

   END SUBROUTINE create_barostat_type

! **************************************************************************************************
!> \brief ...
!> \param barostat ...
!> \par History
!>      09.2007 created [tlaino]
!> \author Teodoro Laino
! **************************************************************************************************
   SUBROUTINE release_barostat_type(barostat)
      TYPE(barostat_type), POINTER                       :: barostat

      LOGICAL                                            :: check

      IF (ASSOCIATED(barostat)) THEN
         check = barostat%ref_count > 0
         CPASSERT(check)
         barostat%ref_count = barostat%ref_count - 1
         IF (barostat%ref_count < 1) THEN
            IF (ASSOCIATED(barostat%npt)) THEN
               DEALLOCATE (barostat%npt)
            END IF
            NULLIFY (barostat%section)
            DEALLOCATE (barostat)
         END IF
      END IF

   END SUBROUTINE release_barostat_type

END MODULE barostat_types
