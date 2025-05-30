!--------------------------------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations                              !
!   Copyright 2000-2025 CP2K developers group <https://cp2k.org>                                   !
!                                                                                                  !
!   SPDX-License-Identifier: GPL-2.0-or-later                                                      !
!--------------------------------------------------------------------------------------------------!

! **************************************************************************************************
MODULE qs_gapw_densities
   USE atomic_kind_types,               ONLY: atomic_kind_type,&
                                              get_atomic_kind
   USE cp_control_types,                ONLY: dft_control_type,&
                                              gapw_control_type
   USE cp_log_handling,                 ONLY: cp_logger_get_default_io_unit
   USE kinds,                           ONLY: dp
   USE message_passing,                 ONLY: mp_para_env_type
   USE pw_env_types,                    ONLY: pw_env_get,&
                                              pw_env_type
   USE pw_pool_types,                   ONLY: pw_pool_p_type
   USE qs_charges_types,                ONLY: qs_charges_type
   USE qs_environment_types,            ONLY: get_qs_env,&
                                              qs_environment_type
   USE qs_kind_types,                   ONLY: get_qs_kind,&
                                              qs_kind_type
   USE qs_local_rho_types,              ONLY: local_rho_type
   USE qs_rho0_ggrid,                   ONLY: put_rho0_on_grid
   USE qs_rho0_methods,                 ONLY: calculate_rho0_atom
   USE qs_rho0_types,                   ONLY: rho0_atom_type,&
                                              rho0_mpole_type
   USE qs_rho_atom_methods,             ONLY: calculate_rho_atom
   USE qs_rho_atom_types,               ONLY: rho_atom_type
   USE realspace_grid_types,            ONLY: realspace_grid_desc_p_type,&
                                              realspace_grid_type
#include "./base/base_uses.f90"

   IMPLICIT NONE

   PRIVATE

   CHARACTER(len=*), PARAMETER, PRIVATE :: moduleN = 'qs_gapw_densities'

   PUBLIC :: prepare_gapw_den

CONTAINS

! **************************************************************************************************
!> \brief ...
!> \param qs_env ...
!> \param local_rho_set ...
!> \param do_rho0 ...
!> \param kind_set_external can be provided to use different projectors/grids/basis than the default
!> \param pw_env_sub ...
! **************************************************************************************************
   SUBROUTINE prepare_gapw_den(qs_env, local_rho_set, do_rho0, kind_set_external, pw_env_sub)

      TYPE(qs_environment_type), POINTER                 :: qs_env
      TYPE(local_rho_type), OPTIONAL, POINTER            :: local_rho_set
      LOGICAL, INTENT(IN), OPTIONAL                      :: do_rho0
      TYPE(qs_kind_type), DIMENSION(:), OPTIONAL, &
         POINTER                                         :: kind_set_external
      TYPE(pw_env_type), OPTIONAL                        :: pw_env_sub

      CHARACTER(len=*), PARAMETER                        :: routineN = 'prepare_gapw_den'

      INTEGER                                            :: handle, ikind, ispin, natom, nspins, &
                                                            output_unit
      INTEGER, DIMENSION(:), POINTER                     :: atom_list
      LOGICAL                                            :: extern, my_do_rho0, paw_atom
      REAL(dp)                                           :: rho0_h_tot, tot_rs_int
      REAL(dp), DIMENSION(:), POINTER                    :: rho1_h_tot, rho1_s_tot
      TYPE(atomic_kind_type), DIMENSION(:), POINTER      :: atomic_kind_set
      TYPE(dft_control_type), POINTER                    :: dft_control
      TYPE(gapw_control_type), POINTER                   :: gapw_control
      TYPE(mp_para_env_type), POINTER                    :: para_env
      TYPE(pw_pool_p_type), DIMENSION(:), POINTER        :: my_pools
      TYPE(qs_charges_type), POINTER                     :: qs_charges
      TYPE(qs_kind_type), DIMENSION(:), POINTER          :: my_kind_set
      TYPE(realspace_grid_desc_p_type), DIMENSION(:), &
         POINTER                                         :: my_rs_descs
      TYPE(realspace_grid_type), DIMENSION(:), POINTER   :: my_rs_grids
      TYPE(rho0_atom_type), DIMENSION(:), POINTER        :: rho0_atom_set
      TYPE(rho0_mpole_type), POINTER                     :: rho0_mpole
      TYPE(rho_atom_type), DIMENSION(:), POINTER         :: rho_atom_set

      CALL timeset(routineN, handle)

      NULLIFY (atomic_kind_set)
      NULLIFY (my_kind_set)
      NULLIFY (dft_control)
      NULLIFY (gapw_control)
      NULLIFY (para_env)
      NULLIFY (atom_list)
      NULLIFY (rho0_mpole)
      NULLIFY (qs_charges)
      NULLIFY (rho1_h_tot, rho1_s_tot)
      NULLIFY (rho_atom_set)
      NULLIFY (rho0_atom_set)

      my_do_rho0 = .TRUE.
      IF (PRESENT(do_rho0)) my_do_rho0 = do_rho0

      output_unit = cp_logger_get_default_io_unit()

      CALL get_qs_env(qs_env=qs_env, dft_control=dft_control, &
                      para_env=para_env, &
                      qs_charges=qs_charges, &
                      qs_kind_set=my_kind_set, &
                      atomic_kind_set=atomic_kind_set, &
                      rho0_mpole=rho0_mpole, &
                      rho_atom_set=rho_atom_set, &
                      rho0_atom_set=rho0_atom_set)

      gapw_control => dft_control%qs_control%gapw_control

      ! If TDDFPT%MGRID is defined, overwrite QS grid info accordingly
      IF (PRESENT(local_rho_set)) THEN
         rho_atom_set => local_rho_set%rho_atom_set
         IF (my_do_rho0) THEN
            rho0_mpole => local_rho_set%rho0_mpole
            rho0_atom_set => local_rho_set%rho0_atom_set
         END IF
      END IF

      extern = .FALSE.
      IF (PRESENT(kind_set_external)) THEN
         CPASSERT(ASSOCIATED(kind_set_external))
         my_kind_set => kind_set_external
         extern = .TRUE.
      END IF

      nspins = dft_control%nspins

      rho0_h_tot = 0.0_dp
      ALLOCATE (rho1_h_tot(1:nspins), rho1_s_tot(1:nspins))
      rho1_h_tot = 0.0_dp
      rho1_s_tot = 0.0_dp

      DO ikind = 1, SIZE(atomic_kind_set)
         CALL get_atomic_kind(atomic_kind_set(ikind), atom_list=atom_list, natom=natom)
         CALL get_qs_kind(my_kind_set(ikind), paw_atom=paw_atom)

         !Calculate rho1_h and rho1_s on the radial grids centered on the atomic position
         IF (paw_atom) THEN
            CALL calculate_rho_atom(para_env, rho_atom_set, my_kind_set(ikind), &
                                    atom_list, natom, nspins, rho1_h_tot, rho1_s_tot)
         END IF

         !Calculate rho0_h and rho0_s on the radial grids centered on the atomic position
         IF (my_do_rho0) &
            CALL calculate_rho0_atom(gapw_control, rho_atom_set, rho0_atom_set, rho0_mpole, &
                                     atom_list, natom, ikind, my_kind_set(ikind), rho0_h_tot)

      END DO

      !Do not mess with charges if using a non-default kind_set
      IF (.NOT. extern) THEN
         CALL para_env%sum(rho1_h_tot)
         CALL para_env%sum(rho1_s_tot)
         DO ispin = 1, nspins
            qs_charges%total_rho1_hard(ispin) = -rho1_h_tot(ispin)
            qs_charges%total_rho1_soft(ispin) = -rho1_s_tot(ispin)
         END DO

         IF (my_do_rho0) THEN
            rho0_mpole%total_rho0_h = -rho0_h_tot

            ! When MGRID is defined within TDDFPT
            IF (PRESENT(pw_env_sub)) THEN
               ! Find pool
               NULLIFY (my_pools, my_rs_grids, my_rs_descs)
               CALL pw_env_get(pw_env=pw_env_sub, rs_grids=my_rs_grids, &
                               rs_descs=my_rs_descs, pw_pools=my_pools)
               ! Put the rho0_soft on the global grid
               CALL put_rho0_on_grid(qs_env, rho0_mpole, tot_rs_int, my_pools=my_pools, &
                                     my_rs_grids=my_rs_grids, my_rs_descs=my_rs_descs)
            ELSE
               ! Put the rho0_soft on the global grid
               CALL put_rho0_on_grid(qs_env, rho0_mpole, tot_rs_int)
            END IF

            IF (ABS(rho0_h_tot) .GE. 1.0E-5_dp) THEN
               IF (ABS(1.0_dp - ABS(tot_rs_int/rho0_h_tot)) .GT. 1.0E-3_dp) THEN
                  IF (output_unit > 0) THEN
                     WRITE (output_unit, '(/,72("*"))')
                     WRITE (output_unit, '(T2,A,T66,1E20.8)') &
                        "WARNING: rho0 calculated on the local grid is  :", -rho0_h_tot, &
                        "         rho0 calculated on the global grid is :", tot_rs_int
                     WRITE (output_unit, '(T2,A)') &
                        "         bad integration"
                     WRITE (output_unit, '(72("*"),/)')
                  END IF
               END IF
            END IF
            qs_charges%total_rho0_soft_rspace = tot_rs_int
            qs_charges%total_rho0_hard_lebedev = rho0_h_tot
         ELSE
            qs_charges%total_rho0_hard_lebedev = 0.0_dp
         END IF
      END IF

      DEALLOCATE (rho1_h_tot, rho1_s_tot)

      CALL timestop(handle)

   END SUBROUTINE prepare_gapw_den

END MODULE qs_gapw_densities
