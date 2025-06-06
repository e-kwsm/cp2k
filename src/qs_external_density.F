!--------------------------------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations                              !
!   Copyright 2000-2025 CP2K developers group <https://cp2k.org>                                   !
!                                                                                                  !
!   SPDX-License-Identifier: GPL-2.0-or-later                                                      !
!--------------------------------------------------------------------------------------------------!
! **************************************************************************************************
!> \brief Routines to handle an external density
!>        The external density can be generic and is provided by user input
!> \author D. Varsano
! **************************************************************************************************
MODULE qs_external_density
   USE cell_types,                      ONLY: cell_type
   USE cp_control_types,                ONLY: dft_control_type
   USE cp_files,                        ONLY: close_file,&
                                              open_file
   USE gaussian_gridlevels,             ONLY: gridlevel_info_type
   USE input_section_types,             ONLY: section_vals_get_subs_vals,&
                                              section_vals_type,&
                                              section_vals_val_get
   USE kinds,                           ONLY: default_string_length,&
                                              dp
   USE pw_env_types,                    ONLY: pw_env_get,&
                                              pw_env_type
   USE pw_methods,                      ONLY: pw_integrate_function
   USE pw_types,                        ONLY: pw_c1d_gs_type,&
                                              pw_r3d_rs_type
   USE qs_environment_types,            ONLY: get_qs_env,&
                                              qs_environment_type
   USE qs_rho_types,                    ONLY: qs_rho_get,&
                                              qs_rho_type
   USE realspace_grid_types,            ONLY: realspace_grid_desc_p_type,&
                                              realspace_grid_type,&
                                              rs_grid_create,&
                                              rs_grid_release,&
                                              rs_grid_zero
   USE rs_pw_interface,                 ONLY: density_rs2pw
#include "./base/base_uses.f90"

   IMPLICIT NONE

   PRIVATE

   CHARACTER(len=*), PARAMETER, PRIVATE :: moduleN = 'qs_external_density'

   PUBLIC :: external_read_density

CONTAINS

! **************************************************************************************************
!> \brief  Computes the external density on the grid
!> \param qs_env ...
!> \date   03.2011
!> \author D. Varsano
! **************************************************************************************************
   SUBROUTINE external_read_density(qs_env)

      TYPE(qs_environment_type), POINTER                 :: qs_env

      CHARACTER(len=*), PARAMETER :: routineN = 'external_read_density'

      CHARACTER(LEN=default_string_length)               :: filename
      INTEGER                                            :: extunit, handle, i, igrid_level, j, k, &
                                                            nat, ndum, tag
      INTEGER, DIMENSION(3)                              :: lbounds, lbounds_local, npoints, &
                                                            npoints_local, ubounds, ubounds_local
      REAL(kind=dp), ALLOCATABLE, DIMENSION(:)           :: buffer
      REAL(kind=dp), DIMENSION(3)                        :: dr, rdum
      REAL(KIND=dp), DIMENSION(:), POINTER               :: tot_rho_r_ext
      TYPE(cell_type), POINTER                           :: cell
      TYPE(dft_control_type), POINTER                    :: dft_control
      TYPE(gridlevel_info_type), POINTER                 :: gridlevel_info
      TYPE(pw_c1d_gs_type), DIMENSION(:), POINTER        :: rho_ext_g
      TYPE(pw_env_type), POINTER                         :: pw_env
      TYPE(pw_r3d_rs_type), DIMENSION(:), POINTER        :: rho_ext_r
      TYPE(qs_rho_type), POINTER                         :: rho_external
      TYPE(realspace_grid_desc_p_type), DIMENSION(:), &
         POINTER                                         :: rs_descs
      TYPE(realspace_grid_type), ALLOCATABLE, &
         DIMENSION(:)                                    :: rs_rho_ext
      TYPE(section_vals_type), POINTER                   :: ext_den_section, input

      CALL timeset(routineN, handle)
      NULLIFY (cell, input, ext_den_section, rs_descs, dft_control)
      NULLIFY (rho_ext_r, rho_ext_g, tot_rho_r_ext)

      CALL get_qs_env(qs_env, &
                      cell=cell, &
                      rho_external=rho_external, &
                      input=input, &
                      pw_env=pw_env, &
                      dft_control=dft_control)

      IF (dft_control%apply_external_density) THEN
         CALL qs_rho_get(rho_external, &
                         rho_r=rho_ext_r, &
                         rho_g=rho_ext_g, &
                         tot_rho_r=tot_rho_r_ext)

         gridlevel_info => pw_env%gridlevel_info

         CALL pw_env_get(pw_env, rs_descs=rs_descs)

         ALLOCATE (rs_rho_ext(gridlevel_info%ngrid_levels))

         DO igrid_level = 1, gridlevel_info%ngrid_levels
            CALL rs_grid_create(rs_rho_ext(igrid_level), &
                                rs_descs(igrid_level)%rs_desc)
            CALL rs_grid_zero(rs_rho_ext(igrid_level))
         END DO

         igrid_level = igrid_level - 1

         ext_den_section => section_vals_get_subs_vals(input, "DFT%EXTERNAL_DENSITY")
         CALL section_vals_val_get(ext_den_section, "FILE_DENSITY", c_val=filename)

         tag = 1
         ASSOCIATE (gid => rho_ext_r(1)%pw_grid%para%group, my_rank => rho_ext_r(1)%pw_grid%para%group%mepos, &
                    num_pe => rho_ext_r(1)%pw_grid%para%group%num_pe)

            IF (dft_control%read_external_density) THEN

               DO i = 1, 3
                  dr(i) = rs_descs(igrid_level)%rs_desc%dh(i, i)
               END DO
               npoints = rs_descs(igrid_level)%rs_desc%npts
               lbounds = rs_descs(igrid_level)%rs_desc%lb
               ubounds = rs_descs(igrid_level)%rs_desc%ub

               npoints_local = rho_ext_r(1)%pw_grid%npts_local
               lbounds_local = rho_ext_r(1)%pw_grid%bounds_local(1, :)
               ubounds_local = rho_ext_r(1)%pw_grid%bounds_local(2, :)

               ALLOCATE (buffer(lbounds_local(3):ubounds_local(3)))

               IF (my_rank == 0) THEN
                  WRITE (*, FMT="(/,/,T2,A)") "INITIALIZING ZMP CONSTRAINED DENSITY METHOD"
                  WRITE (*, FMT="(/,(T3,A,T51,A30))") "ZMP| Reading the target density:     ", filename

                  CALL open_file(file_name=filename, &
                                 file_status="OLD", &
                                 file_form="FORMATTED", &
                                 file_action="READ", &
                                 unit_number=extunit)

                  DO i = 1, 2
                     READ (extunit, *)
                  END DO
                  READ (extunit, *) nat, rdum
                  DO i = 1, 3
                     READ (extunit, *) ndum, rdum
                     IF (ndum /= npoints(i) .OR. (ABS(rdum(i) - dr(i)) > 1e-4)) THEN
                        WRITE (*, *) "ZMP | ERROR! | CUBE FILE NOT COINCIDENT WITH INTERNAL GRID ", i
                        WRITE (*, *) "ZMP | ", ndum, " DIFFERS FROM ", npoints(i)
                        WRITE (*, *) "ZMP | ", rdum, " DIFFERS FROM ", dr(i)
                     END IF
                  END DO
                  DO i = 1, nat
                     READ (extunit, *)
                  END DO
               END IF

               DO i = lbounds(1), ubounds(1)
                  DO j = lbounds(2), ubounds(2)
                     IF (my_rank .EQ. 0) THEN
                        READ (extunit, *) (buffer(k), k=lbounds(3), ubounds(3))
                     END IF
                     CALL gid%bcast(buffer(lbounds(3):ubounds(3)), 0)

                     IF ((lbounds_local(1) .LE. i) .AND. (i .LE. ubounds_local(1)) .AND. (lbounds_local(2) .LE. j) &
                         .AND. (j .LE. ubounds_local(2))) THEN
                        rs_rho_ext(igrid_level)%r(i, j, lbounds(3):ubounds(3)) = buffer(lbounds(3):ubounds(3))
                     END IF

                  END DO
               END DO
               IF (my_rank == 0) CALL close_file(unit_number=extunit)
            END IF

            CALL density_rs2pw(pw_env, rs_rho_ext, rho=rho_ext_r(1), rho_gspace=rho_ext_g(1))
            DO igrid_level = 1, SIZE(rs_rho_ext)
               CALL rs_grid_release(rs_rho_ext(igrid_level))
            END DO
            tot_rho_r_ext(1) = pw_integrate_function(rho_ext_r(1), isign=1)
            IF (my_rank == 0) THEN
               WRITE (*, FMT="(T3,A,T61,F20.10)") "ZMP| Total external charge:                    ", &
                  tot_rho_r_ext(1)
            END IF
            DEALLOCATE (buffer, rs_rho_ext)
            CALL gid%sync()
         END ASSOCIATE
      END IF

      CALL timestop(handle)

   END SUBROUTINE external_read_density

END MODULE qs_external_density

