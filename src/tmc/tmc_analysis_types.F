!--------------------------------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations                              !
!   Copyright 2000-2025 CP2K developers group <https://cp2k.org>                                   !
!                                                                                                  !
!   SPDX-License-Identifier: GPL-2.0-or-later                                                      !
!--------------------------------------------------------------------------------------------------!

! **************************************************************************************************
!> \brief module provides variables for the TMC analysis tool
!> \par History
!>      02.2013 created [Mandes Schoenherr]
!> \author Mandes
! **************************************************************************************************

MODULE tmc_analysis_types
   USE cell_types,                      ONLY: cell_type
   USE kinds,                           ONLY: default_path_length,&
                                              default_string_length,&
                                              dp
   USE tmc_tree_types,                  ONLY: tree_type
   USE tmc_types,                       ONLY: tmc_atom_type
#include "../base/base_uses.f90"

   IMPLICIT NONE

   PRIVATE

   CHARACTER(len=*), PARAMETER, PRIVATE :: moduleN = 'tmc_analysis_types'

   PUBLIC :: tmc_analysis_env, tmc_ana_list_type
   PUBLIC :: tmc_ana_env_create, tmc_ana_env_release
   PUBLIC :: tmc_ana_density_create
   PUBLIC :: pair_correl_type, tmc_ana_pair_correl_create, &
             search_pair_in_list, atom_pairs_type
   PUBLIC :: dipole_moment_type, tmc_ana_dipole_moment_create
   PUBLIC :: tmc_ana_dipole_analysis_create
   PUBLIC :: tmc_ana_displacement_create

   CHARACTER(LEN=default_path_length), PARAMETER, &
      PUBLIC :: tmc_ana_density_file_name = "tmc_ana_density.dat"
   CHARACTER(LEN=default_path_length), PARAMETER, &
      PUBLIC :: tmc_ana_pair_correl_file_name = "tmc_ana_g_r.dat"

   INTEGER, PARAMETER, PUBLIC                      :: ana_type_default = 0
   INTEGER, PARAMETER, PUBLIC                      :: ana_type_ice = 1
   INTEGER, PARAMETER, PUBLIC                      :: ana_type_sym_xyz = 2

   TYPE tmc_ana_list_type
      TYPE(tmc_analysis_env), POINTER               :: temp => NULL()
   END TYPE tmc_ana_list_type

   TYPE tmc_analysis_env
      INTEGER                                       :: io_unit = -1
      CHARACTER(len=default_string_length), &
         DIMENSION(:), POINTER                       :: dirs => NULL()
      CHARACTER(LEN=default_path_length)          :: out_file_prefix = ""
      INTEGER                                       :: conf_offset = 0
      TYPE(cell_type), POINTER                      :: cell => NULL()
      TYPE(tmc_atom_type), DIMENSION(:), POINTER    :: atoms => NULL()
      INTEGER                                       :: dim_per_elem = 3
      INTEGER                                       :: nr_dim = -1
      REAL(KIND=dp)                                 :: temperature = 0.0_dp
      TYPE(tree_type), POINTER                      :: last_elem => NULL()
      INTEGER                                       :: from_elem = -1, to_elem = -1
      INTEGER                                       :: id_traj = -1, id_cell = -1, id_frc = -1, id_dip = -1, id_ener = -1
      INTEGER                                       :: lc_traj = 0, lc_cell = 0, lc_frc = 0, lc_dip = 0, lc_ener = 0
      CHARACTER(LEN=default_path_length)          :: costum_pos_file_name = ""
      CHARACTER(LEN=default_path_length)          :: costum_dip_file_name = ""
      CHARACTER(LEN=default_path_length)          :: costum_cell_file_name = ""
      LOGICAL                                       :: restart = .TRUE., restarted = .FALSE.
      LOGICAL                                       :: print_test_output = .FALSE.

      TYPE(density_3d_type), POINTER                :: density_3d => NULL()
      TYPE(pair_correl_type), POINTER               :: pair_correl => NULL()
      TYPE(dipole_moment_type), POINTER             :: dip_mom => NULL()
      TYPE(dipole_analysis_type), POINTER           :: dip_ana => NULL()
      TYPE(displacement_type), POINTER              :: displace => NULL()
   END TYPE tmc_analysis_env

   TYPE density_3d_type
      INTEGER                                       :: conf_counter = 0
      INTEGER, DIMENSION(3)                         :: nr_bins = 0
      REAL(KIND=dp)                                 :: sum_vol = 0.0_dp
      REAL(KIND=dp)                                 :: sum_vol2 = 0.0_dp
      REAL(KIND=dp), DIMENSION(3)                   :: sum_box_length = 0.0_dp
      REAL(KIND=dp), DIMENSION(3)                   :: sum_box_length2 = 0.0_dp
      REAL(KIND=dp), DIMENSION(:, :, :), POINTER      :: sum_density => NULL(), sum_dens2 => NULL()
      LOGICAL                                       :: print_dens = .TRUE.
   END TYPE density_3d_type

   TYPE pair_correl_type
      INTEGER                                       :: conf_counter = 0
      INTEGER                                       :: nr_bins = 0
      REAL(KIND=dp)                                 :: step_length = -1.0_dp
      TYPE(atom_pairs_type), DIMENSION(:), POINTER  :: pairs => NULL()
      REAL(KIND=dp), DIMENSION(:, :), POINTER        :: g_r => NULL()
      REAL(KIND=dp)                                 :: sum_box_scale(3) = 0.0_dp
   END TYPE pair_correl_type

   TYPE atom_pairs_type
      CHARACTER(LEN=default_string_length)          :: f_n = ""
      CHARACTER(LEN=default_string_length)          :: s_n = ""
      INTEGER                                       :: pair_count = 0
   END TYPE atom_pairs_type

   TYPE dipole_moment_type
      INTEGER                                       :: conf_counter = 0
      TYPE(tmc_atom_type), DIMENSION(:), POINTER    :: charges_inp => NULL()
      REAL(KIND=dp), DIMENSION(:), POINTER          :: charges => NULL()
      REAL(KIND=dp), DIMENSION(:), POINTER          :: last_dip_cl => NULL()
      LOGICAL                                       :: print_cl_dip = .TRUE.
   END TYPE dipole_moment_type

   TYPE dipole_analysis_type
      REAL(KIND=dp)                                 :: conf_counter = 0
      INTEGER                                       :: ana_type = -1
      LOGICAL                                       :: print_diel_const_traj = .TRUE.
      ! squared dipoles per volume
      REAL(KIND=dp)                                 :: mu2_pv_s = 0.0_dp
      ! dipole per square root ov volume per direction
      REAL(KIND=dp), DIMENSION(:), POINTER          :: mu_psv => NULL(), mu_pv => NULL(), mu2_pv => NULL()
      ! dipole dipole correlation matrix (per volume)
      REAL(KIND=dp), DIMENSION(:, :), POINTER        :: mu2_pv_mat => NULL()

   END TYPE dipole_analysis_type

   TYPE displacement_type
      INTEGER                                       :: conf_counter = 0
      REAL(KIND=dp)                                 :: disp = 0.0_dp
      LOGICAL                                       :: print_disp = .TRUE.
   END TYPE displacement_type

CONTAINS

! **************************************************************************************************
!> \brief creates a new structure environment for TMC analysis
!> \param tmc_ana structure with parameters for TMC analysis
!> \author Mandes 02.2013
! **************************************************************************************************
   SUBROUTINE tmc_ana_env_create(tmc_ana)
      TYPE(tmc_analysis_env), POINTER                    :: tmc_ana

      CPASSERT(.NOT. ASSOCIATED(tmc_ana))

      ALLOCATE (tmc_ana)

   END SUBROUTINE tmc_ana_env_create

! **************************************************************************************************
!> \brief releases the structure environment for TMC analysis
!> \param tmc_ana structure with parameters for TMC analysis
!> \author Mandes 02.2013
! **************************************************************************************************
   SUBROUTINE tmc_ana_env_release(tmc_ana)
      TYPE(tmc_analysis_env), POINTER                    :: tmc_ana

      CPASSERT(ASSOCIATED(tmc_ana))

      IF (ASSOCIATED(tmc_ana%dirs)) &
         DEALLOCATE (tmc_ana%dirs)

      IF (ASSOCIATED(tmc_ana%density_3d)) &
         CALL tmc_ana_dens_release(tmc_ana%density_3d)
      IF (ASSOCIATED(tmc_ana%pair_correl)) &
         CALL tmc_ana_pair_correl_release(tmc_ana%pair_correl)

      IF (ASSOCIATED(tmc_ana%dip_mom)) &
         CALL tmc_ana_dipole_moment_release(tmc_ana%dip_mom)

      IF (ASSOCIATED(tmc_ana%dip_ana)) &
         CALL tmc_ana_dipole_analysis_release(tmc_ana%dip_ana)

      IF (ASSOCIATED(tmc_ana%displace)) &
         CALL tmc_ana_displacement_release(ana_disp=tmc_ana%displace)

      DEALLOCATE (tmc_ana)

   END SUBROUTINE tmc_ana_env_release

   !============================================================================
   ! density calculations
   !============================================================================

! **************************************************************************************************
!> \brief creates a new structure environment for TMC analysis
!> \param ana_dens structure with parameters for TMC density analysis
!> \param nr_bins ...
!> \author Mandes 02.2013
! **************************************************************************************************
   SUBROUTINE tmc_ana_density_create(ana_dens, nr_bins)
      TYPE(density_3d_type), POINTER                     :: ana_dens
      INTEGER, DIMENSION(3)                              :: nr_bins

      CPASSERT(.NOT. ASSOCIATED(ana_dens))

      ALLOCATE (ana_dens)

      ana_dens%nr_bins(:) = nr_bins(:)

      ALLOCATE (ana_dens%sum_density(nr_bins(1), nr_bins(2), nr_bins(3)))
      ALLOCATE (ana_dens%sum_dens2(nr_bins(1), nr_bins(2), nr_bins(3)))
      ana_dens%sum_density = 0.0_dp
      ana_dens%sum_dens2 = 0.0_dp
   END SUBROUTINE tmc_ana_density_create

! **************************************************************************************************
!> \brief releases the structure environment for TMC analysis
!> \param ana_dens structure with parameters for TMC analysis
!> \author Mandes 02.2013
! **************************************************************************************************
   SUBROUTINE tmc_ana_dens_release(ana_dens)
      TYPE(density_3d_type), POINTER                     :: ana_dens

      CPASSERT(ASSOCIATED(ana_dens))

      DEALLOCATE (ana_dens%sum_density)
      DEALLOCATE (ana_dens%sum_dens2)
      DEALLOCATE (ana_dens)
   END SUBROUTINE tmc_ana_dens_release

   !============================================================================
   ! radial distribution function
   !============================================================================

! **************************************************************************************************
!> \brief creates a new structure environment for TMC analysis
!> \param ana_pair_correl ...
!> \param nr_bins ...
!> \param
!> \author Mandes 02.2013
! **************************************************************************************************
   SUBROUTINE tmc_ana_pair_correl_create(ana_pair_correl, nr_bins)
      TYPE(pair_correl_type), POINTER                    :: ana_pair_correl
      INTEGER                                            :: nr_bins

      CPASSERT(.NOT. ASSOCIATED(ana_pair_correl))
      ALLOCATE (ana_pair_correl)

      ana_pair_correl%nr_bins = nr_bins
   END SUBROUTINE tmc_ana_pair_correl_create

! **************************************************************************************************
!> \brief releases the structure environment for TMC analysis
!> \param ana_pair_correl ...
!> \param
!> \author Mandes 02.2013
! **************************************************************************************************
   SUBROUTINE tmc_ana_pair_correl_release(ana_pair_correl)
      TYPE(pair_correl_type), POINTER                    :: ana_pair_correl

      CPASSERT(ASSOCIATED(ana_pair_correl))

      DEALLOCATE (ana_pair_correl%g_r)
      DEALLOCATE (ana_pair_correl%pairs)
      DEALLOCATE (ana_pair_correl)
   END SUBROUTINE tmc_ana_pair_correl_release

! **************************************************************************************************
!> \brief search the pair of two atom types in list
!> \param pair_list ...
!> \param n1 atom names
!> \param n2 atom names
!> \param list_end ...
!> \return ...
!> \author Mandes 02.2013
! **************************************************************************************************
   FUNCTION search_pair_in_list(pair_list, n1, n2, list_end) RESULT(ind)
      TYPE(atom_pairs_type), DIMENSION(:), POINTER       :: pair_list
      CHARACTER(LEN=default_string_length)               :: n1, n2
      INTEGER, OPTIONAL                                  :: list_end
      INTEGER                                            :: ind

      INTEGER                                            :: last, list_nr

      CPASSERT(ASSOCIATED(pair_list))
      IF (PRESENT(list_end)) THEN
         CPASSERT(list_end .LE. SIZE(pair_list))
         last = list_end
      ELSE
         last = SIZE(pair_list)
      END IF

      ind = -1

      list_search: DO list_nr = 1, last
         IF ((pair_list(list_nr)%f_n .EQ. n1 .AND. &
              pair_list(list_nr)%s_n .EQ. n2) .OR. &
             (pair_list(list_nr)%f_n .EQ. n2 .AND. &
              pair_list(list_nr)%s_n .EQ. n1)) THEN
            ind = list_nr
            EXIT list_search
         END IF
      END DO list_search
   END FUNCTION search_pair_in_list

   !============================================================================
   ! classical cell dipole moment
   !============================================================================

! **************************************************************************************************
!> \brief creates a new structure environment for TMC analysis
!> \param ana_dip_mom ...
!> \param charge_atm ...
!> \param charge ...
!> \param dim_per_elem ...
!> \param
!> \author Mandes 02.2013
! **************************************************************************************************
   SUBROUTINE tmc_ana_dipole_moment_create(ana_dip_mom, charge_atm, charge, &
                                           dim_per_elem)
      TYPE(dipole_moment_type), POINTER                  :: ana_dip_mom
      CHARACTER(LEN=default_string_length), POINTER      :: charge_atm(:)
      REAL(KIND=dp), POINTER                             :: charge(:)
      INTEGER                                            :: dim_per_elem

      INTEGER                                            :: i

      CPASSERT(.NOT. ASSOCIATED(ana_dip_mom))
      ALLOCATE (ana_dip_mom)

      ALLOCATE (ana_dip_mom%charges_inp(SIZE(charge)))
      DO i = 1, SIZE(charge)
         ana_dip_mom%charges_inp(i)%name = charge_atm(i)
         ana_dip_mom%charges_inp(i)%mass = charge(i)
      END DO

      ALLOCATE (ana_dip_mom%last_dip_cl(dim_per_elem))
      ! still the initialization routine has to be called

   END SUBROUTINE tmc_ana_dipole_moment_create

! **************************************************************************************************
!> \brief releases the structure environment for TMC analysis
!> \param ana_dip_mom ...
!> \param
!> \author Mandes 02.2013
! **************************************************************************************************
   SUBROUTINE tmc_ana_dipole_moment_release(ana_dip_mom)
      TYPE(dipole_moment_type), POINTER                  :: ana_dip_mom

      CPASSERT(ASSOCIATED(ana_dip_mom))

      IF (ASSOCIATED(ana_dip_mom%charges_inp)) DEALLOCATE (ana_dip_mom%charges_inp)
      IF (ASSOCIATED(ana_dip_mom%charges)) DEALLOCATE (ana_dip_mom%charges)
      DEALLOCATE (ana_dip_mom%last_dip_cl)
      DEALLOCATE (ana_dip_mom)
   END SUBROUTINE tmc_ana_dipole_moment_release

! **************************************************************************************************
!> \brief creates a new structure environment for TMC analysis
!> \param ana_dip_ana ...
!> \param
!> \author Mandes 02.2013
! **************************************************************************************************
   SUBROUTINE tmc_ana_dipole_analysis_create(ana_dip_ana)
      TYPE(dipole_analysis_type), POINTER                :: ana_dip_ana

      CPASSERT(.NOT. ASSOCIATED(ana_dip_ana))
      ALLOCATE (ana_dip_ana)

      ALLOCATE (ana_dip_ana%mu_psv(3))
      ana_dip_ana%mu_psv = 0.0_dp
      ALLOCATE (ana_dip_ana%mu_pv(3))
      ana_dip_ana%mu_pv = 0.0_dp
      ALLOCATE (ana_dip_ana%mu2_pv(3))
      ana_dip_ana%mu2_pv = 0.0_dp
      ALLOCATE (ana_dip_ana%mu2_pv_mat(3, 3))
      ana_dip_ana%mu2_pv_mat = 0.0_dp
   END SUBROUTINE tmc_ana_dipole_analysis_create

! **************************************************************************************************
!> \brief releases the structure environment for TMC analysis
!> \param ana_dip_ana ...
!> \param
!> \author Mandes 02.2013
! **************************************************************************************************
   SUBROUTINE tmc_ana_dipole_analysis_release(ana_dip_ana)
      TYPE(dipole_analysis_type), POINTER                :: ana_dip_ana

      CPASSERT(ASSOCIATED(ana_dip_ana))

      DEALLOCATE (ana_dip_ana%mu_psv)
      DEALLOCATE (ana_dip_ana%mu_pv)
      DEALLOCATE (ana_dip_ana%mu2_pv)
      DEALLOCATE (ana_dip_ana%mu2_pv_mat)

      DEALLOCATE (ana_dip_ana)
   END SUBROUTINE tmc_ana_dipole_analysis_release

   !============================================================================
   ! particle displacement in cell (from one configuration to the next)
   !============================================================================

! **************************************************************************************************
!> \brief creates a new structure environment for TMC analysis
!> \param ana_disp ...
!> \param dim_per_elem ...
!> \param
!> \author Mandes 02.2013
! **************************************************************************************************
   SUBROUTINE tmc_ana_displacement_create(ana_disp, dim_per_elem)
      TYPE(displacement_type), POINTER                   :: ana_disp
      INTEGER                                            :: dim_per_elem

      CPASSERT(.NOT. ASSOCIATED(ana_disp))
      CPASSERT(dim_per_elem .GT. 0)
      MARK_USED(dim_per_elem)

      ALLOCATE (ana_disp)

   END SUBROUTINE tmc_ana_displacement_create

! **************************************************************************************************
!> \brief releases a structure environment for TMC analysis
!> \param ana_disp ...
!> \param
!> \author Mandes 02.2013
! **************************************************************************************************
   SUBROUTINE tmc_ana_displacement_release(ana_disp)
      TYPE(displacement_type), POINTER                   :: ana_disp

      CPASSERT(ASSOCIATED(ana_disp))

      DEALLOCATE (ana_disp)
   END SUBROUTINE tmc_ana_displacement_release
END MODULE tmc_analysis_types
